package PPB::Feersum::Tiny;

use strict;
use AnyEvent;
use Cwd ();
use File::Spec::Functions qw( catfile );
use MIME::Type::FileName;


our $VERSION = '0.002'; $VERSION = eval $VERSION;


my @HEADER_PLAIN = ( 'Content-Type', 'text/plain' );
my $READ_BUF_SIZE = 8192;

#
# Parameters:
#  full path to www directory, Feersum request object
#
# Returns: nothing
#
sub send_file($$) {
  my ( $www_dir, $req ) = @_;
  
  my $env = $req->env();
  my $path_info = $env->{ 'PATH_INFO' };
  my $query_string = $env->{ 'QUERY_STRING' } || "";

  if ( $query_string eq '' ) {
    my $file = '';
    
    if ( $path_info eq '/' ) {
      # send index.html
      $file = &Cwd::abs_path( catfile( $www_dir, 'index.html' ) );
    } else {
      $file = &Cwd::abs_path( catfile( $www_dir, $path_info ) );
    }

    # abs_path returns nothing if real path becomes incorrect,
    # i.e. abs_path "/home/../../etc/passwd" == ""
    # But, abs_path "/home/../etc/passwd" == "/etc/passwd"

    if ( $file eq '' ) {
      $req->send_response( 404, \@HEADER_PLAIN, [ 'Not Found' ] );
      return;
    }

    if ( $file =~ /^\Q$www_dir\E/ ) {
      # process files in the directory $www_dir only
      &_send( $req, $file  );
    } else {
      $req->send_response( 400, \@HEADER_PLAIN, [ 'Bad Request' ] );
    }
  } else {
    AE::log trace => "query %s", $query_string;
    $req->send_response( 501, \@HEADER_PLAIN, [ 'Not Implemented' ] );
  }
}

sub _send($$) {
  my ( $req, $file ) = @_;
  
  ( !-d $file ) or do {
    AE::log error => "file %s: it is a directory", $file;
    $req->send_response( 500, \@HEADER_PLAIN, [ 'Internal Server Error' ] );
    return;
  };
  
  ( -e $file ) or do {
    AE::log error => "file %s: %s", $file, $!;
    $req->send_response( 404, \@HEADER_PLAIN, [ 'File Not Found' ] );
    return;
  };
  
  open( my $fh, "<", $file ) or do {
    AE::log error => "open %s: %s", $file, $!;
    $req->send_response( 500, \@HEADER_PLAIN, [ 'Internal Server Error' ] );
    return;
  };
  
  my $type = &MIME::Type::FileName::guess( $file );
  my $w = $req->start_streaming( 200, [ 'Content-Type' => $type ] );
  my $size = -s $fh;
  my $done = 0;
  my $chunk = $size >= $READ_BUF_SIZE ? $READ_BUF_SIZE : $size;
  
  while ( $done < $size ) {
    my $read = read( $fh, my $buf, $chunk );

    if ( defined $read ) {
      $read == 0 and last; # eof
      $w->write( $buf );
    } else {
      AE::log error => "read %s: %s", $file, $!;
      last;
    }
        
    $done += $read;
  }

  $w->close();
  close( $fh )
    or AE::log error => "close %s: %s", $file, $!;
}

scalar "I Need (Policy Story 2)";
