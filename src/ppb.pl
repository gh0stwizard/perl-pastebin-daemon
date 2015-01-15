#!perl

# ppbd - perl pastebin daemon
#
# This is free software; you can redistribute it and/or modify it 
# under the same terms as the Perl 5 programming language system itself.

use strict;
use warnings;
use common::sense;
use EV;
use Feersum;
use AE ();
use AnyEvent::Socket;
use AnyEvent::Handle;
use MongoDB;
use HTTP::Body;
use Digest::JHash;
use Scalar::Util ();
use Encode ();
use JSON::XS ();
use vars qw($VERSION);
#use HTML::Entities; # decode_entities()
#use HTML::Escape; # escape_html()

# Feersum object. Yep, this is our HTTP server ^_-
my $F;

# input data size limits in bytes
sub MIN_BODY_SIZE   { 4      }
sub MAX_BODY_SIZE   { 524288 }

# index.html file to preload and where it will be stored
my $F_INDEX = $ENV{'PPB_INDEX'}  || "/srv/www/ppb/index.html";
my $B_INDEX;

# socket settings
my $BIND    = $ENV{'PPB_LISTEN'} || '127.0.0.1:28950';

# vimbow support
my $VIMBOW  = $ENV{'PPB_VIMBOW'} || '127.0.0.1:28900';
my ($VIMBOW_H, $VIMBOW_P) = split /\:/, $VIMBOW;
my $VIMBOW_ENABLED = $ENV{'PPB_VIMBOW_ENABLED'} || 0;

# mongo db setting. see db_con()
my $DB_SERV = $ENV{'PPB_DBSERV'} || '127.0.0.1:27017';
my $DB_NAME = $ENV{'PPB_DBNAME'} || 'ppb';
my $DB_COLL = $ENV{'PPB_DBCOLL'} || 'posts';

my $MON;    # mongo connection object
my $DB;     # mongo db object
my $CO;     # mongo collection object

# generator counter
my $COUNTER = 0;

# headers
my @H_HTML  = ('Content-Type' => 'text/html; charset=UTF-8');
my @H_JSON  = ('Content-Type' => 'application/json');
my @H_PLAIN = ('Content-Type' => 'text/plain');

sub load_index() {
    if (-e $F_INDEX && !-d $F_INDEX) {
        open(my $fh, "<", $F_INDEX)
            or AE::log fatal => "unable to open %s: %s", $F_INDEX, $!;

        while (<$fh>) {
            $B_INDEX .= $_;
        }

        close $fh;

        AE::log debug => "\`%s\' has been loaded", $F_INDEX;
    } else {
        AE::log fatal => "\`%s\' is invalid index file: %s",
            $F_INDEX, $!;
    }
}

# establish connection to mongo
# open db and collection
sub db_connect() {
    my ($host, $port) = split /\:/, $DB_SERV;
    
    eval {    
        $MON = MongoDB::MongoClient->new(
            host => $host,
            port => $port,
        );
        $DB = $MON->get_database($DB_NAME);
        $CO = $DB->get_collection($DB_COLL);
    };
    
    if ($@) {
        AE::log error => "db connect: $@";
        return;
    }
    
    return 1; 
}

sub get_post_raw($) {
    my ($key) = @_;
    
    my $post;
    
    eval {
        $post = $CO->find_one({ pid => $key }, { data => 1 });
    };

    if ($@) {
        AE::log error => "get_post $key: $@";
        &db_connect();
        return;
    }

    if (delete $post->{_id}) {
        return $post;
    }

    return;
}

sub get_post($$) {
    my ($key, $json_ref) = @_;

    my $post = &get_post_raw($key) || return;
    $$json_ref = JSON::XS::encode_json($post);
    return 1;
}

sub get_post_vimbow($&) {
    my ($key, $cb) = @_;

    if (my $post = &get_post_raw($key)) {
        tcp_connect $VIMBOW_H, $VIMBOW_P, sub {
            my ($fh) = @_;

            if (!defined $fh) {
                AE::log error => "vimbow connect (%s): %s", $key, $!;

                $cb->(\JSON::XS::encode_json($post));
                return;
            }

            my $hdl; $hdl = new AnyEvent::Handle
                fh          => $fh,
                json        => JSON::XS->new(),
                on_error    => sub {
                    my (undef, $fat, $msg) = @_;

                    AE::log error => "vimbow (%s): %s (%s)",
                        $key, $msg, ($fat) ? 'fatal' : 'ignoring';

                    $cb->(\JSON::XS::encode_json($post));
                    $fat and $hdl->destroy();
                },
            ;

            $hdl->push_read(json => sub {
                if ($_[1]->{result}) {
                    utf8::downgrade($_[1]->{result}); # workaround AnyEvent/Handle.pm
                    $cb->(\JSON::XS::encode_json({
                        pid     => $key,
                        data    => Encode::decode_utf8($_[1]->{result}), # workaround AnyEvent/Handle.pm
                    }));
                } else {
                    $cb->(\JSON::XS::encode_json({
                        pid     => $key,
                        err     => delete $_[1]->{error},
                    }));
                }

                $_[0]->destroy();
            });

            $hdl->push_write(json => {
                id      => $key,
                method  => 'colorHTML',
                params  => [ Encode::encode_utf8($post->{data}) ], # XXX: twice mem. size :-\
            });

            #AE::log trace => "vimbow request: %s sent", $key;
        }, sub { 5 }; # timeout
    } else {
        $cb->(\JSON::XS::encode_json({
            pid => $key,
            err => "document not found",
        }));
    }

    return;
}

sub store_data($) {
    my ($data) = @_;

    my $key = Scalar::Util::refaddr($data) . $COUNTER++;
    
    if ($COUNTER > 100_000_000) {
        $COUNTER = 0;
        AE::log note => "internal counter reset";
    }

    # post id
    my $id = $data->{'pid'} = Digest::JHash::jhash($key);

    # XXX: -_-
    $data->{'data'} = Encode::decode_utf8($data->{'data'});

    my $oid;
    
    eval {
        $oid = $CO->insert($data, {safe => 1});
    };
    
    if ($@) {
        AE::log error => "$oid: $@";
        &db_connect();
        return;
    } elsif ($oid) {
        return $id;
    } else {
        return;
    }
}

sub mpost($$$$) {
    my ($r, $len, $type, $json) = @_;

    my $pos = 0;
    my $chunk = ($len > 8192) ? 8192 : $len;

    my $body = HTTP::Body->new($type, $len);
    $body->cleanup(1);

    #TODO
    #$body->tmpdir($TMP_DIR);

    while ($pos < $len) {
        $r->read(my $buf, $chunk);
        $pos += $chunk;
        $body->add($buf);
    }

    $r->close();


    # check that data is correct
    my $p_hash = $body->param();

    if (&MIN_BODY_SIZE() > length($p_hash->{data})) {
        $$json = JSON::XS::encode_json({err => "too few characters"});
    } else {
        # store data in mongo and retrieve uri path
        if (my $id = &store_data($p_hash)) {
            $$json = JSON::XS::encode_json({id => $id});
            return;
        }

        $$json = JSON::XS::encode_json
            ({err => "db error has been occured"});
    }

    return;
}

sub app {
    my $req = shift;

    my $env = $req->env();

    if ($env->{REQUEST_METHOD} eq 'POST') {
        my $t = $env->{CONTENT_TYPE};
        my $l = $env->{CONTENT_LENGTH};
        my $r = delete $env->{'psgi.input'};

        if ($l < 1 || $l > &MAX_BODY_SIZE()) {
            return $req->send_response(
                200,
                \@H_JSON,
                JSON::XS::encode_json({err => "bad request"})
            );
        }

        # paste new note to mongodb and return json with result
        &mpost($r, $l, $t, \my $json);
        $req->send_response(200, \@H_JSON, $json);
    } else {
        if ($env->{PATH_INFO} eq '/') {
            # welcome page
            if ($env->{QUERY_STRING} eq '') {
                # expected json
                $req->send_response(200, \@H_HTML, \$B_INDEX);
                return;
            }

            # request data from db
            my (undef, $id) = split /\=/, $env->{QUERY_STRING}, 2;

            if ($VIMBOW_ENABLED) {
                &get_post_vimbow(int $id, sub {
                    my $w = $req->start_streaming(200, \@H_JSON);
                    $w->write(@_);
                    $w->close();
                });
            } else {
                my $w = $req->start_streaming(200, \@H_JSON);

                if (&get_post(int $id, \my $json)) {
                    $w->write($json);
                } else {
                    $w->write
                        (JSON::XS::encode_json({err => "document not found"}));
                }

                $w->close();
            }
        } else {
            $req->send_response(200, \@H_HTML, \$B_INDEX);
        }
    }
}

sub run_http($) {
    my ($sock) = @_;

    $F ||= Feersum->endjinn;
    $F->use_socket($sock);
    $F->request_handler(\&app);

    AE::log info => "ppb/%s is running", $VERSION;
}

sub create_listener() {
    require Socket;
    require IO::Socket::INET;

    my $sock = new IO::Socket::INET
        LocalAddr   => $BIND,
        ReuseAddr   => 1,
        Proto       => 'tcp',
        Listen      => Socket::SOMAXCONN,
        Blocking    => 0,
    ;

    unless ($sock) {
        AE::log fatal => "couldn't bind to socket: $!";
    }

    AE::log info => "listen on %s", $BIND;

    return $sock;
}

sub startup {
    # micro-main :-)
    &load_index();
    EV::sleep(3) until (&db_connect());
    &run_http(&create_listener());
}

$EV::DIED = $Feersum::DIED = sub {
    AE::log fatal => "$@";
};

&startup();

EV::run; scalar "I want to believe";
