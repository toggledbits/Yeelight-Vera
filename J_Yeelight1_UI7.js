//# sourceURL=J_Yeelight_UI7.js
/**
 * J_Yeelight1_UI7.js
 * Configuration interface for Yeelight
 *
 * Copyright 2019 Patrick H. Rigney, All Rights Reserved.
 * This file is part of Yeelight. For license information, see LICENSE at https://github.com/toggledbits/Yeelight
 */
/* globals api,jQuery,$,MultiBox */

//"use strict"; // fails on UI7, works fine with ALTUI

var Yeelight1_UI7 = (function(api, $) {

    console.log("Initializing Yeelight1_UI7 module");

    /* unique identifier for this plugin... */
    var uuid = '8272ee0a-2629-11e9-a765-74d4351650de'; /* 2019-02-01 Yeelight */

    var myModule = {};

    var serviceId = "urn:toggledbits-com:serviceId:Yeelight1";
    // var deviceType = "urn:schemas-toggledbits-com:device:Yeelight:1";

    var inStatusPanel = false;
    // var isOpenLuup = false;
    // var isALTUI = ( "undefined" !== typeof(MultiBox) );
    var colorProfiles;

    /* Closing the control panel. */
    function onBeforeCpanelClose(args) {
        inStatusPanel = false;
    }

    /* Return footer */
    function footer() {
        var html = '';
        return html;
    }

    function initModule() {
        api.registerEventHandler('on_ui_cpanel_before_close', Yeelight1_UI7, 'onBeforeCpanelClose');
        inStatusPanel = false;

        /* Load material design icons */
        jQuery("head").append('<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">');
    }

    function getSortedDevices(pdev) {
        var dl = api.getListOfDevices();
        var dd = [];
        for ( var ix=0; ix<dl.length; ++ix ) {
            var dobj = dl[ix];
            if ( dobj.id_parent == pdev ) {
                dd.push( dobj );
            }
        }
        dd.sort( function( a, b ) {
            var an = a.name.toLowerCase();
            var bn = b.name.toLowerCase();
            if ( an == bn ) return 0;
            return an < bn ? -1 : 1;
        });
        return dd;
    }
    
    function loadColorProfiles( f ) {
        jQuery.ajax({
            url: api.getDataRequestURL(),
            data: {
                id: "lr_Yeelight",
                action: "listprofiles"
            },
            dataType: "json",
            timeout: 5000
        }).done( function( data, statusText, jqXHR ) {
            f( true, data );
        }).fail( function( jqXHR ) {
            f( false, jqXHR );
        });
    }
    
    function updateProfileMenu() {
        var container = jQuery( 'div#profilesection div' );
        var m = jQuery( 'select#profile', container );
        m.empty();
        var opt;
        var mfg = jQuery( 'select#mfg', container ).val();
        if ( undefined !== colorProfiles.profiles[mfg] ) {
            var p = colorProfiles.profiles[mfg];
            for ( var ix=0; ix<p.length; ix++ ) {
                opt = jQuery( '<option/>').val( p[ix].id ).text(p[ix].id + ' / ' + p[ix].name);
                m.append( opt );
            }
            m.val(p[0].id).trigger( 'change' ); /* Force select first */
        } else {
            jQuery( 'span#luahelp', container ).empty();
        }
    }
    
    function handleProfileChange( ev ) {
        var el = jQuery( ev.currentTarget );
        var row = el.closest( 'div.row' );
        var profile = jQuery( 'select#profile', row ).val();
        var mfg = jQuery( 'select#mfg', row ).val();
        if ( mfg !== "@" ) {
            profile = mfg + profile;
        }
        var dev = api.getCpanelDeviceId();
        var devobj = api.getDeviceObject( dev );
        
        jQuery( 'span#savestatus', row ).empty();
        jQuery( 'span#luahelp' ).empty().append( 'In Lua: <tt>luup.call_action( "' + 
            serviceId + '", "RestoreColorProfile", { DeviceList="' +
            dev + '", ProfileName="' + profile + '" }, ' + devobj.id_parent + ' )</tt>' );
    }
    
    function handleMfgChange( ev ) {
        updateProfileMenu();
    }
    
    function handleRestoreProfileClick( ev ) {
        var el = jQuery( ev.currentTarget );
        var row = el.closest( 'div.row' );
        var profile = jQuery( 'select#profile', row ).val();
        var mfg = jQuery( 'select#mfg', row ).val();
        if ( mfg !== "@" ) {
            profile = mfg + profile;
        }
        var dev = api.getCpanelDeviceId();
        var devobj = api.getDeviceObject( dev );
        
        jQuery( 'span#savestatus', row ).text('');
        api.performActionOnDevice( devobj.id_parent, serviceId, "RestoreColorProfile", 
                { actionArguments: { DeviceList: dev, ProfileName: profile } }
            );
    }
    
    function showColorProfiles( container ) {
        container.empty();
        var m = jQuery( '<select id="mfg" class="form-control form-control-sm" />' );
        var opt;
        for ( var ix=0; ix<colorProfiles.manufacturers.length; ix++ ) {
            opt = jQuery( '<option/>' ).val( colorProfiles.manufacturers[ix].id ).text( colorProfiles.manufacturers[ix].name );
            m.append( opt );
        }
        container.append( m );
        m.val( colorProfiles.manufacturers[0].id ); /* Force select first */
        m.on( 'change.yeelight', handleMfgChange );
        
        container.append( '<select id="profile" class="form-control form-control-sm" />' );
        jQuery( 'select#profile', container ).on( 'change.yeelight', handleProfileChange );
        
        container.append( '<button id="restoreprofile" class="btn btn-sm btn-primary">Set Light Color</button>' );
        jQuery( 'button#restoreprofile', container ).on( 'click.yeelight', handleRestoreProfileClick );
        
        container.append( '<br/><span id="luahelp"/>' );
        
        updateProfileMenu( container );
    }
    

    function handleSaveProfileClick( ev ) {
        var el = jQuery( ev.currentTarget );
        var row = el.closest( 'div.row' );
        var dev = api.getCpanelDeviceId();
        var devobj = api.getDeviceObject( dev );
        var name = jQuery( 'input#saveprofilename', row ).val();
        if ( name.match( /^[a-z].+$/i ) ) {
            // ??? need success/fail handlers
            /* Note that action is performed on parent! */
            jQuery( 'span#savestatus', row ).text(' Wait, saving...');
            api.performActionOnDevice( devobj.id_parent, serviceId, "SaveCurrentColor", 
                { actionArguments: { DeviceNum: dev, ProfileName: name } }
            );
            jQuery( 'span#savestatus', row ).text(' Current color saved!');
            jQuery( 'select#mfg' ).val( '@' );
            updateProfileMenu();
            jQuery( 'select#profile' ).val( name );
        } else {
            jQuery( 'span#savestatus', row ).text(' Invalid profile name. Must start with letter and be longer than one character.');
        }
    }

    function onUIDeviceStatusChanged( args ) {
        if ( !inStatusPanel ) {
            return;
        }
        var pdev = api.getCpanelDeviceId();
        var doUpdate = false;
        for ( var k=0; k<(args.states || []).length; ++k ) {
            if ( args.states[k].service == "urn:upnp-org:serviceId:SwitchPower1" ||
                args.states[k].service == "urn:upnp-org:serviceId:VSwitch1" ) {
                var ix = api.getDeviceObject( args.id );
                if ( ix.id_parent == pdev ) {
                    doUpdate = true;
                    break;
                }
            }
        }
        if ( doUpdate ) {
            // updateStatus( pdev );
        }
    }

    function doColorProfileOne()
    {
        console.log("doColorProfileOne()");

        try {
            initModule();

            /* Our styles. */
            var html = "<style>";
            html += 'div#yeelightstatus {}';
            html += 'div#yeelightstatus div.row { min-height: 40px; margin-top: 4px; margin-bottom: 4px; border-bottom: 1px dotted #006040; }';
            html += 'div#yeelightstatus div.vsname { font-size: 16px; }';
            html += 'div#yeelightstatus i.md-btn { margin-right: 4px; }';
            html += 'div#yeelightstatus i.vstext.md-btn { font-size: 18px; }';
            html += 'div#yeelightstatus div.headrow { color: white; font-size: 16px; font-weight: bold; line-height: 40px; background-color: #00a652; }';
            html += 'div#yeelightstatus div.colhead { }';
            html += "</style>";
            jQuery("head").append( html );

            html = '<div id="yeelightstatus" class="yeelighttab"></div>';
            html += footer();
            api.setCpanelContent( html );

            api.registerEventHandler('on_ui_deviceStatusChanged', Yeelight1_UI7, 'onUIDeviceStatusChanged');
            inStatusPanel = true; /* Tell the event handler it's OK */

            var container = jQuery( 'div#yeelightstatus' );
            var row = jQuery( '<div class="row"/>' );
            var el = jQuery( '<div class="col-xs-12 form-inline"/>' );
            el.append( '<h3>Save Color</h3><label for="saveprofilename">Save current color to profile: <input id="saveprofilename" class="form-control form-control-sm"></label><button id="saveprofile" class="btn btn-sm btn-primary">Save Color</button><span id="savestatus"/>' );
            row.append( el );
            container.append( row );
            
            container.append( '<h3>Restore Profile Color</h3><div id="profilesection" class="row"><div class="col-xs-12 form-inline">Loading color profiles...</div></div>' );
            
            jQuery( 'button#saveprofile', container ).on( 'click.switchboard', handleSaveProfileClick );            

            loadColorProfiles( function( success, data ) {
                if ( success ) {
                    colorProfiles = data;
                    showColorProfiles( jQuery( 'div#profilesection div' ) );
                } else {
                    jQuery( 'div#profilesection div' ).text('Unable to load color profiles. Try again in a few seconds, Luup may be reloading.');
                }
            });
        }
        catch( e ) {
            alert( String(e) + "\n" + e.stack );
        }
    }

/** ***************************************************************************
 *
 * C L O S I N G
 *
 ** **************************************************************************/

    myModule = {
        uuid: uuid,
        initModule: initModule,
        onBeforeCpanelClose: onBeforeCpanelClose,
        onUIDeviceStatusChanged: onUIDeviceStatusChanged,
        doColorProfileOne: doColorProfileOne
    };
    return myModule;
})(api, $ || jQuery);
