//# sourceURL=J_Yeelight_UI7.js
/**
 * J_Yeelight1_UI7.js
 * Configuration interface for Yeelight
 *
 * Copyright 2019 Patrick H. Rigney, All Rights Reserved.
 * This file is part of Yeelight. For license information, see LICENSE at https://github.com/toggledbits/Yeelight-Vera
 */
/* globals api,jQuery,$,MultiBox,application,Utils */

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

    function jq( id ) {
        return "#" + id.replace( /([^a-z0-9_-])/ig, "\\$1" );
    }

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

    function getSortedChildren(pdev) {
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

    function onUIDeviceStatusChanged( args ) {
        if ( !inStatusPanel ) {
            return;
        }
        var pdev = api.getCpanelDeviceId();
        var dobj = api.getDeviceObject( args.id );
        if ( dobj.id_parent == pdev ) {
            console.log("Update received for "+String(args.id));
            for ( var k=0; k<(args.states || []).length; ++k ) {
                var st = args.states[k];
                if ( st.service == "urn:upnp-org:serviceId:SwitchPower1" &&
                     st.variable == "Status" ) {
                    jQuery( 'div#d' + args.id + '.devicerow img#state' ).attr( 'src',
                        'https://www.toggledbits.com/assets/yeelight/yeelight-lamp-' +
                    ( st.value=="0" ? "off" : "on" ) + '.png' );
                } else if ( st.service == "urn:toggledbits-com:serviceId:Yeelight1" &&
                        st.variable == "HexColor" ) {
                    jQuery( 'div#d' + args.id + '.devicerow div#colorspot' )
                        .css( 'background-color', '#' + st.value )
                        .attr( 'title', st.value );
                }
            }
        }
    }

    function loadColorProfiles( f ) {
        jQuery.ajax({
            url: api.getDataRequestURL(),
            data: {
                id: "lr_Yeelight",
                action: "listprofiles",
                rnd: Math.random()
            },
            dataType: "json",
            timeout: 5000,
            cache: false
        }).done( function( data, statusText, jqXHR ) {
            f( true, data );
        }).fail( function( jqXHR ) {
            f( false, jqXHR );
        });
    }

    function updateProfileMenu( container ) {
        var m = jQuery( 'select#profile', container );
        m.empty();
        var opt;
        var mfg = jQuery( 'select#mfg', container ).val();
        var p = colorProfiles.profiles[mfg] || [];
        for ( var ix=0; ix<p.length; ix++ ) {
            opt = jQuery( '<option/>').val( p[ix].id ).text(p[ix].id + ' / ' + p[ix].name);
            m.append( opt );
        }
        jQuery( 'option:first', m ).prop( 'selected', true ); /* Force select first */
    }

    function handleMfgChange( ev ) {
        var row = jQuery( ev.currentTarget ).closest( 'div.row' );
        updateProfileMenu( row );
    }

    /**
     * Show the loaded color profiles in the standard menus
     */
    function showColorProfiles( container ) {
        var m = jQuery( 'select#mfg', container ).empty();
        var opt;
        for ( var ix=0; ix<colorProfiles.manufacturers.length; ix++ ) {
            if ( ( colorProfiles.profiles[ colorProfiles.manufacturers[ix].id ] || [] ).length > 0 ) {
                opt = jQuery( '<option/>' ).val( colorProfiles.manufacturers[ix].id ).text( colorProfiles.manufacturers[ix].name );
                m.append( opt );
            }
        }
        jQuery( 'option:first', m ).prop( 'selected', true ); /* Force select first */

        updateProfileMenu( container );
    }

    function handleMasterLightToggle( ev ) {
        var el = jQuery( ev.currentTarget );
        var row = el.closest( 'div.devicerow' );
        var dev = parseInt( row.attr( 'id' ).replace( /^d/i, "" ) );
        api.performActionOnDevice( dev, "urn:micasaverde-com:serviceId:HaDevice1", "ToggleState", { actionArguments: {} });
    }

    function handleMasterCheckToggle( ev ) {
        var el = jQuery( ev.currentTarget );
        if ( el.text() == 'warning' ) {
            el.removeClass( 'tbchecked' );
        } else if ( el.text() == 'check_box' ) {
            el.text( 'check_box_outline_blank' ).removeClass( 'tbchecked' );
        } else {
            el.text( 'check_box' ).addClass( 'tbchecked' );
        }
    }

    function handleMasterSetProfile( ev ) {
        var container = jQuery( 'div#yeemasterlights' );

        var devicelist = [];
        jQuery( 'i.tbchecked', container ).each( function( ix, obj ) {
            var devnum = jQuery( obj ).closest( 'div.devicerow' ).attr( 'id' );
            devnum = devnum.replace( /^d/i, "" );
            devicelist.push( devnum );
        });
        if ( devicelist.length < 1 ) {
            alert("Please select one or more lights first.");
            return;
        }

        var profile = jQuery( 'select#profile', container ).val();
        var mfg = jQuery( 'select#mfg', container ).val();
        if ( '@' !== mfg ) {
            profile = mfg + profile;
        }
        devicelist = devicelist.join( ',' );
        var myid = api.getCpanelDeviceId();
        api.performActionOnDevice( myid, serviceId, "RestoreColorProfile",
            { actionArguments: { DeviceList: devicelist, ProfileName: profile } }
        );
        jQuery( 'div#legend', container ).empty().append('In Lua: <tt>luup.call_action( "' +
            serviceId + '", "RestoreColorProfile", { DeviceList="' + devicelist +
            '", ProfileName="' + profile + '" }, ' + myid + ' )</tt>' );
    }

    function doMasterLightsTab()
    {
        console.log("doMasterLightsTab()");

        try {
            initModule();

            /* Our styles. */
            var html = "<style>";
            html += 'div#yeemasterlights {}';
            html += 'div#yeemasterlights div.headrow { min-height: 48px; margin-top: 4px; margin-bottom: 4px; border: 1px solid #00a652; border-radius: 4px; }';
            html += 'div#yeemasterlights div.headrow { color: white; font-size: 16px; line-height: 48px; background-color: #00a652; }';
            html += 'div#yeemasterlights div.devicerow { min-height: 36px; line-height: 36px; margin-top: 4px; margin-bottom: 4px; border-bottom: 1px dotted #006040; }';
            html += 'div#yeemasterlights div.devicerow i.md-btn { font-size: 24px; line-height: 36px; }';
            html += 'div#yeemasterlights div#colorspot { margin: 4px 4px 4px 4px; border: 2px solid black; height: 32px; width: 100%; }';
            html += "</style>";
            jQuery("head").append( html );

            html = '<div id="yeemasterlights" class="yeelighttab"></div>';
            html += footer();
            api.setCpanelContent( html );

            var container = jQuery( 'div#yeemasterlights' );
            var row = jQuery( '<div class="row headrow"/>' );
            var el = jQuery( '<div id="actions" class="col-xs-12 col-sm-12 form-inline"/>' );
            el.append("Profile: ");
            el.append('<select id="mfg" class="form-control form-control-sm"/>');
            el.append('<select id="profile" class="form-control form-control-sm"/>');
            el.append('<button id="setprofile" class="btn btn-sm btn-primary">Apply to selected lights</button>');
            row.append( el );
            container.append( row );

            var lights = getSortedChildren( api.getCpanelDeviceId() );
            var st;
            for ( var ix=0; ix<lights.length; ix++ ) {
                row = jQuery( '<div class="row devicerow" />' ).attr('id', 'd'+lights[ix].id );
                el = jQuery( '<div class="col-xs-1 col-sm-1 text-center" />' );
                el.append( '<i id="checked" class="material-icons md-btn" title="Select/deselect for action">check_box_outline_blank</i>' );
                row.append( el );
                el = jQuery( '<div class="col-xs-1 col-sm-1 text-center" />' );
                st = api.getDeviceState( lights[ix].id, "urn:upnp-org:serviceId:SwitchPower1", "Status" ) || "0";
                el.append( jQuery( '<img id="state" src="https://www.toggledbits.com/assets/yeelight/yeelight-lamp-' +
                    ( st=="0" ? "off" : "on" ) + '.png" width="32" height="32" alt="switch state">' )
                    .attr( 'title', 'Click to toggle state' )
                );
                row.append( el );
                el = jQuery( '<div class="col-xs-1 col-sm-1"><div id="colorspot" title="current color" /></div>' );
                st = api.getDeviceState( lights[ix].id, "urn:toggledbits-com:serviceId:Yeelight1", "HexColor" ) || "000000";
                jQuery( 'div#colorspot', el ).css( 'background-color', '#' + st ).attr( 'title', st );
                row.append( el );
                el = jQuery( '<div class="col-xs-9 col-sm-9" />' ).text( lights[ix].name + ' (#' + lights[ix].id + ')' );
                row.append( el );
                container.append( row );
            }

            jQuery( 'i#checked', container).on( 'click.yeelight', handleMasterCheckToggle );
            jQuery( 'img#state', container ).on( 'click.yeelight', handleMasterLightToggle );

            container.append('<div class="row"><div id="legend" class="col-xs-12 col-sm-12" /></div>');

            api.registerEventHandler('on_ui_deviceStatusChanged', Yeelight1_UI7, 'onUIDeviceStatusChanged');
            inStatusPanel = true; /* Tell the event handler it's OK */

            loadColorProfiles( function( success, data ) {
                var ct = jQuery( 'div#yeemasterlights div#actions' );
                if ( success ) {
                    colorProfiles = data;
                    showColorProfiles( ct );
                    jQuery( 'button#setprofile', ct ).on( 'click.yeelight', handleMasterSetProfile );
                    jQuery( 'select#mfg', ct ).on( 'change.yeelight', handleMfgChange );
                    jQuery( 'select#profile', ct ).on( 'change.yeelight', handleProfileChange );
                } else {
                    ct.empty().text( "Unable to load profiles; Luup may be restarting. Try again in a few moments." );
                }
            });
        }
        catch( e ) {
            alert( String(e) + "\n" + e.stack );
        }
    }

    function handleProfileAction( ev ) {
        var el = jQuery( ev.currentTarget );
        var action = el.attr('id');
        var row = el.closest( 'div.profilerow' );
        var id = row.attr( 'id' );
        var myid = api.getCpanelDeviceId();

        switch ( action ) {
            case 'deleteprofile':
                var st = api.getDeviceState( myid, serviceId, "LocalColorProfiles" ) || "{}";
                var custom = JSON.parse( st );
                if ( undefined !== custom && undefined !== custom[id] ) {
                    delete custom[id];
                    api.setDeviceStatePersistent( myid, serviceId, "LocalColorProfiles", JSON.stringify( custom ) ); // ??? success/failure?
                    row.remove();
                }
                break;

            default:
                // nada
        }
    }

    function handleSliderStop( event, ui ) {
        var slider = jQuery( ui.handle ).closest( '.tbslide' );
        // var value = slider.slider( "option", "value" );
        // var which = slider.attr('id');

        var demo = parseInt( jQuery( 'select#demolamp' ).val() );
        if ( ! isNaN( demo ) ) {
            var r = jQuery( 'div#redslide.tbslide' ).slider( "option", "value" );
            var g = jQuery( 'div#greenslide.tbslide' ).slider( "option", "value" );
            var b = jQuery( 'div#blueslide.tbslide' ).slider( "option", "value" );
            var rgb = [r,g,b].join(',');
            api.performActionOnDevice( demo, "urn:micasaverde-com:serviceId:Color1",
                "SetColorRGB", { actionArguments: { newColorRGBTarget: rgb } } );
        }
    }

    function handleProfileRename( ev ) {
        var row = jQuery( ev.currentTarget ).closest( 'div.profilerow' );
        var name = row.attr( 'id' );
        var myid = api.getCpanelDeviceId();
        var st = api.getDeviceState( myid, serviceId, "LocalColorProfiles" ) || "{}";
        var custom = JSON.parse( st );

        var newname = name;
        while (true) {
            newname = prompt( "Enter new name:", newname );
            if ( undefined == newname ) {
                return;
            }
            if ( ! newname.match( /^\w.+$/i ) ) {
                continue;
            }
            if ( undefined == custom[newname] ) {
                custom[newname] = custom[name];
                delete custom[name];
                api.setDeviceStatePersistent( myid, serviceId, "LocalColorProfiles", JSON.stringify( custom ) ); // ??? success/failure?
                jQuery( 'span#profilename', row ).text( newname );
                row.attr( 'id', newname );
                return;
            }
        }
    }

    function handleProfileEdit( ev ) {
        var row = jQuery( ev.currentTarget ).closest( 'div.profilerow' );
        var name = row.attr( 'id' );
        jQuery( 'input#newprofile' ).val( name );
        var st = jQuery( ev.currentTarget ).text() || "0,0,0";
        st = st.split( /,/ );
        for ( var k=0; k<st.length; k++ ) {
            st[k] = parseInt( st[k] );
            if ( isNaN( st[k] ) ) {
                st[k] = 0;
            }
        }
        jQuery( 'div#redslide.tbslide' ).slider( "option", "value", st[0] );
        jQuery( 'div#greenslide.tbslide' ).slider( "option", "value", st[1] );
        jQuery( 'div#blueslide.tbslide' ).slider( "option", "value", st[2] );
    }

    function handleAddProfileClick( ev ) {
        var row = jQuery( ev.currentTarget ).closest( 'div.row' );
        var name = jQuery( 'input#newprofile', row ).val() || "";
        if ( ! name.match( /^\w.+$/i ) ) {
            alert( "Invalid profile name. Must be two or more characters, first must be a letter." );
            return;
        }

        var r = jQuery( 'div#redslide.tbslide', row ).slider( "option", "value" );
        var g = jQuery( 'div#greenslide.tbslide', row ).slider( "option", "value" );
        var b = jQuery( 'div#blueslide.tbslide', row ).slider( "option", "value" );
        var rgb = [r,g,b].join(',');

        var myid = api.getCpanelDeviceId();
        var st = api.getDeviceState( myid, serviceId, "LocalColorProfiles" ) || "{}";
        var custom = JSON.parse( st );
        if ( undefined !== custom ) {
            custom[ name ] = rgb;
            api.setDeviceStatePersistent( myid, serviceId, "LocalColorProfiles", JSON.stringify( custom ) ); // ??? success/failure?
            var nr = jQuery( 'div.profilerow' + jq( name ) );
            if ( nr.length > 0 ) {
                /* Row exists with same name/ID (saving/editing existing profile) */
                jQuery( 'span#more', nr ).text( rgb );
                return;
            }
            /* This is a new profile */
            nr = jQuery( '<div class="row profilerow"/>' ).attr( 'id', name );
            nr.append( '<div class="col-xs-1 col-sm-1"><i id="deleteprofile" class="material-icons md-btn">clear</i></div>' );
            nr.append( '<div class="col-xs-11 col-sm-11"><span id="profilename"/> = <span id="more"/></div>' );
            jQuery( 'span#profilename', nr ).text( name );
            jQuery( 'span#more', nr ).text( rgb );
            nr.insertBefore( row );
            jQuery( 'i.md-btn', nr ).on( 'click.yeelight', handleProfileAction );
            jQuery( 'span#profilename', nr ).on( 'click.yeelight', handleProfileRename );
            jQuery( 'span#more', nr ).on( 'click.yeelight', handleProfileEdit );
        }
    }

    function doMasterProfilesTab() {
        console.log("doMasterProfilesTab()");

        try {
            initModule();

            /* Our styles. */
            var html = "<style>";
            html += 'div#yeemasterprofiles {}';
            html += 'div#yeemasterprofiles div.headrow { min-height: 48px; margin-top: 4px; margin-bottom: 4px; border: 1px solid #00a652; border-radius: 4px; }';
            html += 'div#yeemasterprofiles div.headrow { color: white; font-size: 16px; line-height: 48px; background-color: #00a652; }';
            html += 'div#yeemasterprofiles div.profilerow { min-height: 36px; line-height: 36px; margin-top: 4px; margin-bottom: 4px; border-bottom: 1px dotted #006040; }';
            html += 'div#yeemasterprofiles div.profilerow i.md-btn { font-size: 24px; line-height: 36px; }';
            html += 'div#yeemasterprofiles div#colorspot { margin: 4px 4px 4px 4px; border: 2px solid black; height: 32px; width: 100%; }';
            html += 'div#yeemasterprofiles div.tbslide { height: 8px; width: 100%; margin-top: 8px; margin-bottom: 12px; }';
            html += 'div#yeemasterprofiles div.tbslide .ui-slider-handle { background: transparent url(https://www.toggledbits.com/assets/yeelight/slider-handle.png) no-repeat scroll 50% 50%; margin-top: 0px; }';
            html += 'div#yeemasterprofiles div#redslide.ui-slider .ui-slider-range { background-color: red; }';
            html += 'div#yeemasterprofiles div#greenslide.ui-slider .ui-slider-range { background-color: green; }';
            html += 'div#yeemasterprofiles div#blueslide.ui-slider .ui-slider-range { background-color: blue; }';
            html += "</style>";
            jQuery("head").append( html );

            html = '<div id="yeemasterprofiles" class="yeelighttab"></div>';
            html += footer();
            api.setCpanelContent( html );

            var container = jQuery( 'div#yeemasterprofiles' );
            var row = jQuery( '<div class="row headrow"/>' );
            var el = jQuery( '<div id="actions" class="col-xs-2 col-sm-2"/>' );
            row.append( el );
            el = jQuery( '<div class="col-xs-10 col-sm-10" />' );
            row.append( el );
            container.append( row );

            var st = api.getDeviceState( api.getCpanelDeviceId(), serviceId, "LocalColorProfiles" ) || "{}";
            var custom = JSON.parse( st ) || {};
            for ( var id in custom ) {
                if ( !custom.hasOwnProperty( id ) ) continue;
                var p = custom[id];
                row = jQuery( '<div class="row profilerow" />' ).attr('id', id );
                el = jQuery( '<div class="col-xs-1 col-sm-1" />' );
                el.append( '<i id="deleteprofile" class="material-icons md-btn" title="Delete Profile">clear</i>' );
                row.append( el );
                el = jQuery( '<div class="col-xs-11 col-sm-11" />' );
                el.append( jQuery( '<span id="profilename" />' ).text(id) );
                el.append( ' = ' );
                el.append( jQuery( '<span id="more" />' ).text( p ) );
                row.append( el );
                container.append( row );
            }

            row = jQuery( '<div class="row"/>' );
            el = jQuery( '<div class="col-xs-3 col-sm-3 form-inline"/>' );
            el.append( '<label for="demolamp">Demo Lamp: <select id="demolamp" class="form-control form-control-sm" /></label>' );
            row.append( el );
            el = jQuery( '<div class="col-xs-4 col-sm-4 form-inline"/>' );
            el.append( '<label for="newprofile">New Profile Name: <input id="newprofile" class="form-control form-control-sm"></label>' );
            el.append( '<button id="addprofile" class="btn btn-sm btn-primary">Save</button>' );
            row.append( el );
            el = jQuery( '<div class="col-xs-5 col-sm-5"/>' );
            el.append( '<div id="redslide" class="tbslide" />' );
            el.append( '<div id="greenslide" class="tbslide" />' );
            el.append( '<div id="blueslide" class="tbslide" />' );
            row.append( el );
            container.append( row );

            jQuery( 'div.tbslide', container ).slider({
                range: "min",
                min: 0,
                max: 255,
                step: 1,
                value: 0,
                change: handleSliderStop,
                start: function(event, ui) {},
                slide: function(event, ui) {},
                stop: handleSliderStop
            });

            var lights = getSortedChildren( api.getCpanelDeviceId() );
            var m = jQuery( 'select#demolamp', container ).empty();
            m.append( jQuery( '<option/>' ).val("").text("--none--") );
            for ( var ix=0; ix<lights.length; ix++ ) {
                m.append( jQuery( '<option/>' ).val( lights[ix].id ).text( lights[ix].name + ' (#' + lights[ix].id + ')' ) );
            }

            jQuery( 'button#addprofile', container ).on( 'click.yeelight', handleAddProfileClick );

            jQuery( 'i#deleteprofile', container ).on( 'click.yeelight', handleProfileAction );

            jQuery( 'span#profilename', container ).on( 'click.yeelight', handleProfileRename );

            jQuery( 'span#more', container ).on( 'click.yeelight', handleProfileEdit );

            container.append('<div class="row"><div id="legend" class="col-xs-12 col-sm-12" /></div>');

            jQuery( 'div#legend', container ).text( 'The "demo lamp", if selected, will change color with the sliders. To change a profile name, click the name. To change a profile\'s color, click its color.' );
        }
        catch( e ) {
            alert( String(e) + "\n" + e.stack );
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

    function handleLightRestoreClick( ev ) {
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

    function handleSaveProfileClick( ev ) {
        var el = jQuery( ev.currentTarget );
        var row = el.closest( 'div.row' );
        var dev = api.getCpanelDeviceId();
        var devobj = api.getDeviceObject( dev );
        var name = jQuery( 'input#saveprofilename', row ).val();
        if ( name.match( /^\w.+$/i ) ) {
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

    function doColorProfileOne()
    {
        console.log("doColorProfileOne()");

        try {
            initModule();

            /* Our styles. */
            var html = "<style>";
            html += 'div#yeelightstatus {}';
            html += "</style>";
            jQuery("head").append( html );

            html = '<div id="yeelightstatus" class="yeelighttab"></div>';
            html += footer();
            api.setCpanelContent( html );

            var container = jQuery( 'div#yeelightstatus' );
            var row = jQuery( '<div class="row"/>' );
            var el = jQuery( '<div class="col-xs-12 col-sm-12 form-inline"/>' );
            el.append( '<h3>Save Color</h3><label for="saveprofilename">Save current color to profile: <input id="saveprofilename" class="form-control form-control-sm"></label><button id="saveprofile" class="btn btn-sm btn-primary">Save Color</button><span id="savestatus"/>' );
            row.append( el );
            container.append( row );

            container.append( '<h3>Restore Profile Color</h3>' );
            row = jQuery( '<div class="row" />' );
            el = jQuery( '<div id="profilesection" class="col-xs-12 col-sm-12 form-inline"/>' );
            el.append( '<select id="mfg" class="form-control form-control-sm"><option value="" disabled>Loading...</option></select>' );
            el.append( '<select id="profile" class="form-control form-control-sm"><option value="" disabled>Loading...</option></select>' );
            el.append( '<button id="restoreprofile" class="btn btn-sm btn-primary">Set Color from Profile</button>' );
            el.append( '<br/><span id="luahelp"/>' );
            row.append( el );
            container.append( row );

            jQuery( 'button#saveprofile', container ).on( 'click.yeelight', handleSaveProfileClick );
            jQuery( 'button#restoreprofile' ).prop( 'disabled', true );

            loadColorProfiles( function( success, data ) {
                if ( success ) {
                    colorProfiles = data;
                    var container = jQuery( 'div#profilesection' );
                    showColorProfiles( container );
                    jQuery( 'button#restoreprofile', container ).prop( 'disabled', false ).on( 'click.yeelight', handleLightRestoreClick );
                    jQuery( 'select#mfg', container ).on( 'change.yeelight', handleMfgChange );
                    jQuery( 'select#profile', container ).on( 'change.yeelight', handleProfileChange );
                } else {
                    jQuery( 'div#profilesection' ).text('Unable to load color profiles. Try again in a few seconds, Luup may be reloading.');
                }
            });
        }
        catch( e ) {
            alert( String(e) + "\n" + e.stack );
        }
    }

    function doAfterInit() {
        /* Replace broken UI7 function */
        if ( undefined !== application && undefined !== application.isDimmableRGBLight ) {
            console.log("Replacing broken UI7 isDimmableRGBLight()");
            application.isDimmableRGBLight = function( device ) {
                try {
                    if ( void 0 === device && void 0 === device.device_json ) return false;
                    if ( "2" === device.category_num && "4" === device.subcategory_num ) return true;
                    if ( "urn:schemas-upnp-org:device:DimmableRGBLight:1" === device.device_type ) return true;
                    /* Do what Vera's native function does as a last resort. BTW, this omits one of their own files in 1040: D_DimmableRGBOnlyLight1.json. Oh well. */
                    return "D_DimmableRGBLight1.json" === device.device_json || "D_DimmableRGBLight2.json" === device.device_json;
                } catch (e) {
                    Utils.logError("Application.isDimmableRGBLight(): " + e);
                }
                return !1;
            };
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
        doColorProfileOne: doColorProfileOne,
        doMasterLightsTab: doMasterLightsTab,
        doMasterProfilesTab: doMasterProfilesTab,
        doAfterInit: doAfterInit
    };
    return myModule;
})(api, $ || jQuery);
