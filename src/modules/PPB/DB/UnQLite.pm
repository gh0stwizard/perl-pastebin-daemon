package PPB::DB::UnQLite;

#
# UnQLite database backend for ppb
#

use strict;
use UnQLite;
use File::Spec::Functions ();

our $VERSION = '0.001'; $VERSION = eval $VERSION;


my $BASEDIR = ( exists $ENV{ 'PPB_BASEDIR' } )
  ? $ENV{ 'PPB_BASEDIR' }
  : '.';

my $INSTANCE;


{
#
# keep db open all the time
#
  my $db_file = &File::Spec::Functions::catfile( $BASEDIR, 'ppb.db' );
  my $db_flags = &UnQLite::UNQLITE_OPEN_READWRITE();
  
  #
  # UnQLite <= 0.05 does not check file permissions
  # and does not throw errors.
  #
  # We must be sure that able to open (read, write) file.
  #
  if ( -e $db_file ) {
    # file exists, check perms
    unless ( -r $db_file && -w $db_file && -o $db_file ) {
      die "Check permissions on $db_file: $!";
    }
  } else {
    # file does not exists, try to create file
    open ( my $fh, ">", $db_file )
      or die "Failed to open $db_file: $!";
    syswrite( $fh, "test\n", 5 )
      or die "Failed to write $db_file: $!";
    close( $fh )
      or die "Failed to close $db_file: $!";
    open ( my $fh, "<", $db_file )
      or die "Failed to open $db_file: $!";    
    sysread( $fh, my $buf, 5 )
      or die "Failed to read $db_file: $!";
    close( $fh )
      or die "Failed to close $db_file: $!";
    unlink( $db_file )
      or die "Failed to remove $db_file: $!";
    
    # auto create database file
    $db_flags |= &UnQLite::UNQLITE_OPEN_CREATE();
  }
  
  $INSTANCE = UnQLite->open( $db_file, $db_flags );
}

sub store($$) {
  #my ( $post_id, $data ) = @_;
  
  # returns 1 if success
  # returns undef if failed
  return $INSTANCE->kv_store( $_[0], $_[1] );
}

sub fetch($) {
  #my ( $post_id ) = @_;
  
  return $INSTANCE->kv_fetch( $_[0] );
}

sub delete_all() {
  my $cursor = $INSTANCE->cursor_init();
  
  for ( $cursor->first_entry(); $cursor->valid_entry(); $cursor->next_entry() ) {
    $cursor->delete_entry();
  }
  
  return;
}

sub entries() {
  my $cursor = $INSTANCE->cursor_init();
  
  my $entries = 0;
  for ( $cursor->first_entry(); $cursor->valid_entry(); $cursor->next_entry() ) {
    $entries++;
  }
  
  return $entries;
}

scalar "Cold Chord (Human Element Remix)";
