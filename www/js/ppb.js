$( document ).ready( function() {
  // auto-resize textarea
  var $mh = $( "#main" ).height();
  var $h = $( window ).height() - $mh - 39;
  $( "textarea" ).height( $h );

  var $pb = $( "#progressbar" );
  var $max_pb = 50;
  var $default_inc_pb = 25;
  var $inc_pb = $default_inc_pb;
  var $srv_suffix = '/ppb';

  var $pathname = window.location.pathname;
  var $addr = window.location.protocol + '//' + window.location.host;

  // decrease font size on mobiles
  if ( $.browser.mobile ) {
    $( "#error p" ).css( 'font-size', '1em' );
    $( "#link a" ).css( 'font-size', '1em' );
  }

  function pb_done() {
    $pb.progressbar( "value", 100 );
  };

  function show_url( postid ) {
    $( "#link" ).append("<a></a>");

    var url = $addr + '/' + postid;

    $( "#link a" )
    .attr( "href", url )
    .attr( "title", "post id: " + postid )
    .append( url );

    $( "#link a").show( 'drop', {}, 500, pb_done );
  };

  function show_error( string ) {
    $( "#error" ).append( "<p>" + string + "</p>" );
    $( "#error p" ).show( 'drop', {}, 500, pb_done );
  };

  function reset_all() {
    $( "#error" ).empty();
    $( "#link" ).empty();
    $inc_pb = $default_inc_pb;
    $pb.progressbar( "value", 0 );
    $pb.show();
    setTimeout( progress, 100 );
  };

  // checks progress bar value
  function check_pb() {
    var pbvalue = $pb.progressbar( "value" ) || 0;

    if ( pbvalue == 0 ) {
      return false;
    }

    if ( $max_pb > 90 ) {
      setTimeout( progress, 100 );
      return false;
    }

    if ( pbvalue > $max_pb && pbvalue < 100 ) {
      $max_pb += $inc_pb;
      setTimeout( progress, 100 );
    } else {
      setTimeout( check_pb, 100 );
    }
  };

  // limit progress bar speed
  // makes it a bit slow
  function progress() {
    var pbvalue = $pb.progressbar( "value" ) || 0;

    if ( pbvalue == 75 ) {
      $inc_pb = 10;
    }

    if ( pbvalue == 95 ) {
      $inc_pb = 1;
    }

    if ( pbvalue == 99 ) {
      return false;
    }

    $pb.progressbar( "value", pbvalue + $inc_pb );

    if ( pbvalue < $max_pb ) {
      setTimeout( progress, 100 );
    } else {
      setTimeout( check_pb, 100 );
    }
  };

  function load_post() {
    reset_all();

    // store current height before hide
    var height = $( "textarea" ).height() - 22;

    $( "textarea" ).hide();
    $( "#area" ).hide();
    
    // request post via GET
    var url = $addr + $srv_suffix + "?q=" + $pathname.substring( 1 );

    $.getJSON( url, function( json ) {
      if ( json.id ) {
        $( "#area" ).append( $.parseHTML( "<pre>" + json.data + "</pre>" ) );
        $( "#area pre" ).height( height );

        $( "#area" ).show( 'clip', {}, 300, function() {
          $( "#area pre" ).click( function() {
            $( "#area pre" ).attr( 'contenteditable', true );
          } );
        } );
      } else {
        show_error( json.err );
      }
    } );
  };

  function create_post() {
    reset_all();

    $( "#send" ).button( "disable" );

    $.post( $srv_suffix, $( "#postForm" ).serialize(),
      function( data ) {
        if ( data.id ) {
          show_url( data.id );
        } else {
          show_error( data.err );
        }
      }
    ), "json";
  };

  $( "#send" ).click( create_post );
  
  // ctrl + enter in textarea sends request
  // to create new post
  function MessageTextOnKeyEnter( e ) {
    if ( e.keyCode == 13 && e.ctrlKey ) {
      create_post();
    }
  };

  if ( $pathname.length > 1 ) {
    load_post();
  } else {
    $( "#send" ).removeAttr( "disabled" );
    $( "textarea" ).keydown( MessageTextOnKeyEnter ).focus();
  }
} ); // document.ready
  
$( window ).resize( function() {
  var $h = $( window ).height() - $( "#main" ).height() - 24;
  $( "textarea" ).height( $h );
} );

$( function() {
  $( "button" ).button( {
      icons: { primary: "ui-icon-triangle-1-e" }
  } );
} );

$( function() {
  var pbsetup = {
    value: true,
    change: function() {
      $( ".progress-label" )
      .text( $( "#progressbar" ).progressbar( "value" ) + "%" );
    },
    complete: function() {
      $( "#progressbar" ).hide( 'fade', 100, function() {
        $( "#send" ).button( "enable" );
        $( "textarea" ).focus();
      } );
    }
  };

  $( "#progressbar" ).progressbar( pbsetup );
} );
