#!/usr/bin/perl

# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.

use strict;
use common::sense;
use Feersum;
use EV;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Socket ();
use vars qw( $PROGRAM_NAME $VERSION );

my %CURRENT_SETTINGS;
my %DEFAULT_SETTINGS =
(
  'LISTEN'    => '127.0.0.1:28950',
  'APP_NAME'  => 'app+feersum.pl',
  'SOMAXCONN' => &Socket::SOMAXCONN(),
);


{
  my $t; $t = AE::timer 0, 0, sub {
    undef $t;
    &start_server();
  };
  
  my %signals; %signals = 
  (
    'HUP' => sub {
      AE::log alert => "SIGHUP recieved, reload";
      &reload_server();
    },
    'INT' => sub {
      AE::log alert => 'SIGINT recieved, shutdown';
      %signals = ();
      &shutdown_server();
    },
    'TERM' => sub {
      AE::log alert => 'SIGTERM recieved, shutdown';
      %signals = ();
      &shutdown_server();
    },
  );
  
  for my $name ( keys %signals ) {
    my $cb = $signals{ $name };
    $signals{ $name } = AE::signal $name => $cb;
  }
  
  $EV::DIED = $Feersum::DIED = sub {
    AE::log fatal => "$@";
  };
}

&EV::run();

# ---------------------------------------------------------------------
  
sub start_server() {
  &enable_syslog();
  &debug_settings();
  &update_settings();  
  &start_httpd();
  
  AE::log note => "Listen on %s:%d, PID = %d",
    parse_listen(),
    $$,
  ;
}

sub shutdown_server() {
  &stop_httpd();
  &EV::unloop();
}

sub reload_server() {
  &reload_syslog();  
  &stop_httpd();
  &start_httpd();

  AE::log note => "Server restarted, PID = %d", $$;
}

sub update_settings() {
  for my $var ( keys %DEFAULT_SETTINGS ) {
    my $envname = join '_', uc( $PROGRAM_NAME ), $var;
    
    $CURRENT_SETTINGS{ $var } = defined $ENV{ $envname }
      ? $ENV{ $envname }
      : $DEFAULT_SETTINGS{ $var }
    ;
  }
}

sub enable_syslog() {
  my $facility = &get_syslog_facility() || return;
  
  &Sys::Syslog::openlog
  (
    $PROGRAM_NAME,
    'ndelay,pid', # nodelay, include pid
    $facility,
  );
}

sub reload_syslog() {
  my $facility = &get_syslog_facility() || return;
  
  &Sys::Syslog::closelog();
  &Sys::Syslog::openlog
  (
    $PROGRAM_NAME,
    'ndelay,pid',
    $facility,
  );
}

sub get_syslog_facility() {
  $ENV{ 'PERL_ANYEVENT_LOG' } =~ m/syslog=([_\w]+)$/ or return;
  return "$1";
}

{
  my $Instance;
  
  sub start_httpd() {
    $Instance ||= Feersum->endjinn();

    my ( $addr, $port ) = parse_listen();
    my $socket = &create_socket( $addr, $port );
      
    if ( my $fd = fileno( $socket ) ) {
      $Instance->accept_on_fd( $fd );
      $Instance->set_server_name_and_port( $addr, $port );
      $Instance->{ 'socket' } = $socket;
      $Instance->request_handler( &load_app() );
      return;
    }

    AE::log fatal => "Could not retrieve fileno %s:%d: %s",
      $addr, $port, $!;
  }
  
  sub stop_httpd() {
    if ( ref $Instance eq 'Feersum' ) {
      $Instance->request_handler( \&app_service_unavailable );
      $Instance->unlisten();
      close( delete $Instance->{ 'socket' } )
        or AE::log error => "Failed to close listen socket: %s", $!;
    }
  }
}

sub app_internal_error {
  $_[0]->send_response
  (
    500,
    [ 'Content-Type' => 'text/html' ],
    [ 'Internal Server Error' ],
  );
}

sub app_service_unavailable {
  $_[0]->send_response
  (
    503,
    [ 'Content-Type' => 'text/html' ],
    [ 'Service Unavailable' ],
  );
}

sub create_socket($$) {
  my ( $addr, $port ) = @_;

  my $proto = &AnyEvent::Socket::getprotobyname( 'tcp' );

  socket
  (
    my $socket,
    &Socket::PF_INET,
    &Socket::SOCK_STREAM,
    $proto,
  ) or do {
    AE::log fatal => "Could not create socket %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };
  
  setsockopt
  (
    $socket,
    &Socket::SOL_SOCKET(),
    &Socket::SO_REUSEADDR(),
    pack( "l", 1 ),
  ) or AE::log error => "Could not setsockopt SO_REUSEADDR %s:%d: %s",
    $addr,
    $port,
    $!,
  ;
  
  setsockopt
  (
    $socket,
    &Socket::SOL_SOCKET(),
    &Socket::SO_KEEPALIVE(),
    pack( "I", 1 ),
  ) or AE::log error => "Could not setsockopt SO_KEEPALIVE %s:%d: %s",
    $addr,
    $port,
    $!,
  ;
  
  require AnyEvent::Util;
  &AnyEvent::Util::fh_nonblocking( $socket, 1 );

  my $sa = &AnyEvent::Socket::pack_sockaddr
  (
    $port,
    &AnyEvent::Socket::aton( $addr ),
  );
  
  bind( $socket, $sa ) or do {
    AE::log fatal => "Could not bind %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };
  
  listen( $socket, $CURRENT_SETTINGS{ 'SOMAXCONN' } ) or do {
    AE::log fatal => "Could not listen %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };
  
  return $socket;
}

sub parse_listen() {
  my ( $cur_addr, $cur_port ) = split ':', $CURRENT_SETTINGS{ 'LISTEN' };
  my ( $def_addr, $def_port ) = split ':', $DEFAULT_SETTINGS{ 'LISTEN' };
  
  $cur_addr ||= $def_addr;
  $cur_port ||= $def_port;
  
  return( $cur_addr, $cur_port );
}


sub load_app() {
  my $file = $CURRENT_SETTINGS{ 'APP_NAME' } || $DEFAULT_SETTINGS{ 'APP_NAME'};
  my $app = do( $file );
  
  if ( ref $app eq 'CODE' ) {
    return $app;
  }
      
  if ( $@ ) {
    AE::log error => "Couldn't parse %s: %s", $file, "$@";
  }
      
  if ( $! && !defined $app ) {
    AE::log error => "Couldn't do %s: %s", $file, $!;
  }
      
  if ( !$app ) {
    AE::log error => "Couldn't run %s", $file;
  }
  
  return \&app_internal_error;
}

sub debug_settings() {
  AE::log debug => "INC[0] = %s", $INC[0];
  
  my @envopts = 
  (
    'PERL_ANYEVENT_LOG',
    join( '_', uc( $PROGRAM_NAME ), 'WWW_DIR' ),
    join( '_', uc( $PROGRAM_NAME ), 'BASEDIR' ),
  );
  AE::log debug => "%s = %s", $_, $ENV{ $_ } || "" for ( @envopts );
  
  AE::log debug => "%s = %s",
    $_,
    $CURRENT_SETTINGS{ $_ } for ( sort keys %CURRENT_SETTINGS );  
}

scalar "Gameboy Megamix!";
