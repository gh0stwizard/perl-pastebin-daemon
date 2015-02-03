use strict;
use common::sense;
use AnyEvent;
use HTTP::Body ();
use JSON::XS ();
use Math::BigInt ();
use PPB::DB::UnQLite;

# body checks
my $MIN_BODY_SIZE = 4;
my $MAX_BODY_SIZE = 524288;

# http headers for responses
my @HEADER_JSON = ( 'Content-Type' => 'application/json; charset=UTF-8' );
my @HEADER_PLAIN = ( 'Content-Type' => 'text/plain' );

# www dir with index.html (standalone mode)
my $WWW_DIR = $ENV{ join( '_', uc( $PROGRAM_NAME ), 'WWW_DIR' ) };


sub app {
  my $req = shift;

  my $env = $req->env();
  my $method = $env->{ 'REQUEST_METHOD' };

  if ( $method eq 'POST' ) {
    my $type = $env->{ 'CONTENT_TYPE' };
    my $len = $env->{ 'CONTENT_LENGTH' };
    my $r = delete $env->{ 'psgi.input' };
    
    my $w =$req->start_streaming( 200, \@HEADER_JSON );
    $w->write( &create_post( $r, $len, $type ) );
    $w->close();
  } elsif ( $method eq 'GET' ) {
    if ( my $query = $env->{ 'QUERY_STRING' } ) {
      AE::log trace => "query: %s", $query;

      if ( $query =~ /^json=(\w{1,16})$/ ) {
        my $w = $req->start_streaming( 200, \@HEADER_JSON );
        $w->write( &load_post( $1 ) );
        $w->close();
      } else {
        &_501( $req );
      }
    } else {
      # when working standalone, i.e. without nginx
      require PPB::Feersum::Tiny;
      &PPB::Feersum::Tiny::send_file( $WWW_DIR, $req );
    }
  } else {
    &_405( $req );
  }
  
  return;
}

sub create_post($$$) {
  my ( $r, $len, $type ) = @_;
  
  my %response;
  
  if ( $len > 0 ) {
    my $body = read_body( $r, $len, $type );
    my $params = $body->param();
    my $body_len = length $params->{ 'data' };
    
    if ( $body_len >= $MAX_BODY_SIZE ) {
      %response = ( 'err' => "too big message" );
    } elsif ( $body_len <= $MIN_BODY_SIZE ) {
      %response = ( 'err' => "too few characters" );
    } else {
      if ( my $post_id = &store_post( $params ) ) {
        %response = ( 'id' => $post_id );
        
        AE::log trace => "post %s stored, total: %d",
          $post_id,
          &PPB::DB::UnQLite::entries();
      } else {
        %response = ( 'err' => "failed to store post" );
      }
    }
  } else {
    %response = ( err => "bad request" );
  }
  
  return &JSON::XS::encode_json( \%response );
}

#
# Parameters:
#   HTTP::Body object
#
# Returns: 
#   post id (string) or nothing
#
sub store_post($) {
  my ( $params ) = @_;
  
  my $post_id = &gen_post_id();
  &PPB::DB::UnQLite::store( $post_id, $params->{ 'data' } ) || return;  
  return $post_id;
}

{
#
# TODO
# * add hostname or something machine-specific
#
  my $counter = 1;
  
  sub gen_post_id() {
    return &num2alphanum
    (
      $$,
      int( &AE::time() - $^T ),
      $counter++,
    );
  }
}

#
# converts number to alphanum string
#  
sub num2alphanum(@) {
  my @results;
  
  foreach my $key ( @_ ) {
    my ( $quo, $rem ) = ( int $key, 0 );
    # 62 chars: 0..9, a-z, A-Z
    my $div = 61;
    my @alphanum;

    while ( $quo > $div ) {
      my $big = Math::BigInt->new( $quo );
      ( $quo, $rem ) = $big->bdiv( $div );
      
      if ( $rem < 10 ) {
        push @alphanum, pack "c", $rem + 48;
      } elsif ( $rem < 36 ) {
        push @alphanum, pack "c", $rem + 55;
      } else {
        push @alphanum, pack "c", $rem + 61;
      }
    }

    if ( $quo < 10 ) {
      push @alphanum, pack "c", $quo + 48;
    } elsif ( $quo < 36 ) {
      push @alphanum, pack "c", $quo + 55;
    } else {
      push @alphanum, pack "c", $quo + 61;
    }
    
    push @results, join( '', @alphanum );
  }
    
  return wantarray
    ? @results
    : join( '', @results );
}

#
# converts alpha-numeric string to number
#
sub alphanum2num(@) {
  my @results;
  my $mult = 61;
  
  for my $string ( @_ ) {
    my @chars = split //, $string;
    my $number = 0;
    
    for ( my $i = 0; $i < @chars; $i++ ) {
      my $num = unpack( "c", $chars[$i] );
      
      if ( $num < 58 ) {
        $number += ( $num - 48 ) * $mult ** $i;
      } elsif ( $num < 91 ) {
        $number += ( $num - 55 ) * $mult ** $i;
      } else {
        $number += ( $num - 61 ) * $mult ** $i;
      }
    }

    push @results, $number;
  }
  
  return wantarray
    ? @results
    : join( "$," , @results );
}
    
#
# read HTTP request body
#
sub read_body($$$) {
  my ( $r, $len, $type ) = @_;

  my $body = HTTP::Body->new( $type, $len );
  # TODO
  # $body->tmpdir( $TMP_DIR );
  $body->cleanup( 1 );
  
  my $pos = 0;
  my $chunk = ( $len > 8192 ) ? 8192 : $len;

  while ( $pos < $len ) {
    $r->read( my $buf, $chunk ) or last;
    $body->add( $buf );
    $pos += $chunk;
  }

  $r->close();
  
  return $body;
}

sub load_post($) {
  my ( $post_id ) = @_;
  
  my %response;
  
  if ( my $data = &PPB::DB::UnQLite::fetch( $post_id ) ) {
    %response = ( "id" => $post_id, "data" => $data );
  } else {
    %response = ( "err" => "not found" );
  }
  
  return &JSON::XS::encode_json( \%response );
}

\&app;
