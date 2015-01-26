package PPB::Feersum::Tiny;

use strict;
use AnyEvent;
use Cwd qw( abs_path );
use File::Spec::Functions qw( catfile );
use File::LibMagic ();


our $VERSION = '0.001'; $VERSION = eval $VERSION;


my @HEADER_PLAIN = ( 'Content-Type', 'text/plain' );
my @HEADER_HTML = ( 'Content-Type', 'text/html' );
my $READ_BUF_SIZE = 8192;
my $MAGIC_FILE = catfile( $ENV{ 'PPB_BASEDIR' }, "perl.magic" );


#
# Parameters:
#  full path to www directory, Feersum request object
#
# Returns: nothing
#
sub send_file() {
  my ( $www_dir, $req ) = @_;
  
  my $env = $req->env();
  my $path_info = $env->{ 'PATH_INFO' };
  my $query_string = $env->{ 'QUERY_STRING' } || "";
  my $file = '';
  
  if ( $path_info eq '/' && $query_string eq '' ) {
    # send index.html
    $file = abs_path catfile( $www_dir, 'index.html' );
  } else {
    $file = abs_path catfile( $www_dir, $path_info );
  }
  
  #AE::log trace => "sending %s", $file;
  
  &_send( $req, $file );
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
  
  my $type = File::LibMagic
      ->new( $MAGIC_FILE )
      ->info_from_filename( $file )
      ->{ 'mime_type' };
  
  AE::log trace => "mime for %s: %s", $file, $type;
  
  my $w = $req->start_streaming( 200, [ 'Content-Type' => $type ] );
  my $size = -s $fh;
  my $done = 0;
  my $chunk = $size >= $READ_BUF_SIZE ? $READ_BUF_SIZE : $size;
  
#  $w->poll_cb( sub {
#    my $read = read( $fh, my $buf, $chunk );
#
#    if ( defined $read ) {
#      if ( $read == 0 ) {
#        close $fh;
#        $w->close();
#      } else {
#        $w->write( $buf );
#      }
#    } else {
#      AE::log error => "read %s: %s", $file, $!;
#      close $fh;
#      $w->close();
#    }
#  } );

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
