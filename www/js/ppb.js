$(document).ready(function() {
    var $mh = $( "#main" ).height();
    var $h = $(window).height() - $mh - 39;
    $( "textarea" ).height($h);
    
    var progressbar = $( "#progressbar" );
    var $max_pb = 50;
    var $inc_pb = 5;
        
    // decrease font size on mobiles
    if ($.browser.mobile) {
        $( "#main p" ).css('font-size', '1em');
        $( "#main input" )
            .css('font-size', '1em')
            .attr('size', 28);
    }
                
    function hide_error() {
        $( "#area pre" ).remove();
        $( "#main p" )
            .removeClass('ui-state-error')
            .hide('drop', {}, 500, cb_show);
        return false;
    }
        
    function hide_input() {
        $( "#main input" ).hide('drop', {}, 500, cb_show);
        return false;
    }
        
    // callback function to bring an error message
    function cb_hide() {        
        $( "#hide" )
            .click(hide_error)
            .show('highlight', 1000);
        return false;
    };
    
    // for ie, mobile and non-flash
    function cb_hide_input() {
        progressbar.progressbar("value", 0).hide();
        
        $( "#hide" )
            .click(hide_input)
            .show('highlight', {}, 500, function () {
                $( "#send" ).button("option", "disabled", true);
            });
    };
                
    //callback function to hide error message
    function cb_show() {
        $( "#area" ).show();
        $( "textarea" ).show('fold', {}, 500, function () {
            $( "textarea" ).focus();
            progressbar.progressbar("value", 0).hide();
            $( "#send" ).button("option", "disabled", false);
            $( "#hide" ).hide();
        });
    };
    
    function show_error(string) {
        $( "#main p" )
            .empty()
            .append("Error: " + string)
            .addClass("ui-state-error")
            .show('drop', {}, 500, cb_hide);
    };

    function after_copy() {
        $("#main input")
            .css('background', '#1c94c4')
            .val("Link has been copied")
            .effect('highlight', {}, 1000, function() {
                setTimeout(function () {
                    progressbar.progressbar("value", 0).hide();
                    
                    $( "#send" ).button("option", "disabled", false);
                    $( "#main input" )
                        .hide('blind', {'direction': 'left'}, 500, function() {
                            $( "#main input" )
                                .empty()
                                .css('background', '#f6a828 url(images/ui-bg_gloss-wave_35_f6a828_500x100.png) 50% 50% repeat-x')
                                .zclip('remove');
                        });
                }, 1500);
            });
    };

    function show_url() {
        progressbar.progressbar("value", 0);
        
        if (navigator.userAgent.indexOf('MSIE') != -1
                || $.browser.mobile || !FlashDetect.installed) {
            $( "#main input" ).select();
            return cb_hide_input();
        } else {
            $( "#main input" ).zclip({
                path: '/js/ZeroClipboard.swf',
                copy: function() { return $("#main input").val(); },
                afterCopy: after_copy
            });
        }
    };
    
    function check_pb() {
        var $val = progressbar.progressbar( "value" ) || 0;
        
        if ($val == 0) {
            return false;
        }
        
        if ($max_pb > 90) {
            setTimeout( progress, 100 );
            return false;
        }
            
        if ($val > $max_pb && $val < 100) {
            $max_pb += 5;
            setTimeout( progress, 100 );
        } else {
            setTimeout( check_pb, 100 );
        }
    };
    
    function progress() {
      var val = progressbar.progressbar( "value" ) || 0;
      
      if (val == 70) {
        $inc_pb = 2;
      }
      
      if (val == 85 ) {
        $inc_pb = 1;
      }
      
      if (val == 98) {
        return false;
      }
      
      progressbar.progressbar( "value", val + $inc_pb );
      
      if ( val < $max_pb ) {
        setTimeout( progress, 100 );
      } else {
        setTimeout( check_pb, 100 );
      }
    };
            
    $( "#send" ).click(function() {
        $( "#send" ).button("option", "disabled", true);
        
        progressbar.show();
        setTimeout( progress, 100 );
            
        $.post('/', $( "#postForm" ).serialize(), function(data) {
            progressbar.progressbar("value", 100);
            
            if (data.id) {                    
                var $uri = window.location.protocol 
                    + '//' 
                    + window.location.host 
                    + '/'
                    + data.id;
                    
                $( "#main input" )
                    .val($uri)
                    .show('drop', {}, 500, show_url);
            } else {
                show_error(data.err);
            }
        }), "json";
    });

    // retrieve document if needed
    var $cur = window.location.pathname;
        
    if ($cur.length > 1) {
        progressbar.show();
        setTimeout( progress, 100 );
        
        var $url = "/?q=" + $cur.substring(1);
        // store current height
        var $h = $( "textarea" ).height() - 22;
        
        $( "textarea" ).hide();
        $( "#area" ).hide();
        
        $.getJSON($url, function(json) {
            $( "#hide" ).show('highlight', 1000);
            
            progressbar.progressbar("value", 100);

            if (json.data) {
                html = $.parseHTML("<pre>" + json.data + "</pre>");
                $( "#area" ).append(html);      // fill text
                $( "#area pre" ).height($h);    // restore height
                
                $( "#area" ).show('clip', {}, 300, function() {                    
                    $( "#area pre" ).click(function() {
                        $( "#area pre" ).attr('contenteditable', true);
                    });
                });
                
                $( "#hide" ).click(function() {
                    $( "#area pre" ).removeAttr('contenteditable');
                    $( "#area pre" ).remove();
                    progressbar.progressbar("value", 0).hide();
                    $( "textarea" ).show('fold', {}, 500, function () {
                        $( "textarea" ).focus();
                        $( "#send" ).button("option", "disabled", false);
                        $( "#hide" ).hide();
                    });
                });
                
                $(window).resize(function() {
                    var $h = $(window).height() - $( "#main" ).height() - 52;
                    $( "#area" ).height($h);
                    $( "#area pre" ).height($h);
                });
            } else {
                show_error(json.err);
            }
        });
    } else {
        $( "#send" ).removeAttr("disabled");
        $( "textarea" ).focus();
    }
}); // document.ready
  
$(window).resize(function() {
    var $h = $(window).height() - $( "#main" ).height() - 24;
    $( "textarea" ).height($h);
});
  
$(function() {
    $( "button").button({
        icons: {
            primary: "ui-icon-triangle-1-e"
        }
    });
});

$(function() {
    var progressbar = $( "#progressbar" ),
        progressLabel = $( ".progress-label" );
    
    progressbar.progressbar({
        value: true,
        change: function() {
            progressLabel.text( progressbar.progressbar( "value" ) + "%");
        },
        complete: function() {
            progressbar.hide('fade', 500);
        }
    });
});