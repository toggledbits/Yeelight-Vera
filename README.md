# Yeelight-Vera

A plugin for Vera Home Automation Controllers to control Yeelight bulbs and fixtures.

## Installation

To install this plugin:
* Download a release package from the Github repository;
* Unzip the files;
* Upload the files to your Vera using the uploader at *Apps > Develop apps > Luup files*
* If this is the first time installing the plugin, create the master device:
  * Go to *Apps > Develop apps > Create device*
  * Enter `Yeelight Plugin` in the *Description* field;
  * Enter `D_Yeelight1.xml` in the *Upnp Device Filename* field;
  * Enter `I_Yeelight1.xml` in the *Upnp Implementation Filename* field;
  * Leave all other fields blank (you may set the room if you wish), and press the *Create device* button.
  * Go to *Apps > Develop apps > Test Luup code (Lua)* and enter `luup.reload()` and run it.
  * Hard-refresh/reload your browser (with cache flush). You should now see the Yeelight Plugin master device.

### Additional Instructions for openLuup

openLuup does not have some of Vera's "native" service files and device type declarations used by this plugin.
To get this plugin working under openLuup, you will need to download
`D_DimmableRGBLight1.json` and `D_DimmableRGBLight1.xml` (uncompressed, not the compressed *.lzo* versions)
and put them in your openLuup installation directory.

## Finding Devices

The Yeelight plugin does discovery of devices using Yeelight's twist on SSDP. Before launching discovery,
however, you have to use the Yeelight application (Android, iOS, etc.) to enable "LAN Control" on each device. To do this:
* Open the Yeelight application;
* Register any new devices you may have added but are not yet shown in the app;
* Tap on the device/bulb in the device list;
* Click the icon that looks like a media eject button;
* Click the "LAN Control" icon;
* Turn LAN control ON;
* POWER CYCLE THE YEELIGHT DEVICE. Many users have found that the bulbs are not discoverable until you reboot them. Aren't we living in a magical age?
* Repeat these steps for each additional device.

To discover your controllable devices, go to
the Yeelight Plugin master device control panel, and click the *Run Discovery* button. Discovery will then launch,
and takes about 15 seconds. It will create child devices for any Yeelight device that responds (see caution below).

## Controlling Devices

Controlling discovered devices uses the Vera-standard "RGB Dimmable Light" services and user interface (so don't blame me).
From this interface, you can control on/off, brightness, color temperature, and RGB color.

Different products have different
limits for these values, and Vera has its own limits; not everything that is possible for the device may be possible through
the interface, and not everything that the interface can do may be possible on the bulb. The most notable is color temperature,
where the Yeelight API allows temperatures down to 1600&deg;K, but Vera's lower limit is 2000K; and Vera's upper limit is 9000K,
where Yeelight's API maximum is 6500K.

If a device is controlled using interfaces other than plugin, there may be a noticeable delay before the plugin shows the device
status. Updates are not immediate; the API has to be polled, and the default polling interval is 300 seconds (5 minutes). If this
proves inconvenient, you can change the `UpdateInterval` state variable in the bulb device, or to change it for all bulbs, on the master
device. Keep in mind, however, that very small intervals (less than 60 seconds), may increase the load on your Vera (for likely
very little average benefit).

## Special Features

### Gel Colors

The plugin has conversion tables for approximations of various color gels (Roscolux, Lee Filters, and GamColor). By using the
`SetColor` action (in service `urn:micasaverde-com:serviceId:Color1`) and passing a specially formatted string, you can have the plugin set the bulb to a named or numbered color. The
format is "!_xn_", where "!" is a literal exclamation mark, _x_ is the manufacturer code (currently R=Roscolux, L=Lee Filters, G=GamColor),
and _n_ is the numeric code or string color name. For example, "!r66" sets Roscolux "cool blue", which could also be done by sending
"!rcool blue". Note that case is not significant in these strings for the manufacturer or color name.

It should go without saying that this use of the `SetColor` action is an extension by this plugin, and this feature is unlikely to be supported in products not controlled by this plugin. But there's a workaround if you're working with both Yeelight and non-Yeelight bulbs... see below.

### Named Color Profiles

Key to the implementation of gel colors is named color profiles. Named color profiles are simply an association of a name with an r,g,b triplet that defines the color. The gel colors are just pre-defined named colors. It is also possible, however, to have custom named colors.

On each light, the "Color Profile" tab allows you to save the current color to a named profile, or restore a saved color profile. On the Yeelight plugin master device, there are similar interfaces that let you save the color of any of the controlled lights, or restore a color from a named profile to a set of lights. All of the gel colors available are stored as named profiles and can be accessed through this interface.

The plugin defines two actions in its service (`urn:toggledbits-com:serviceId:Yeelight1`) that are used to implement this feature: `SaveCurrentColor` and `RestoreColorProfile`.

The `SaveCurrentColor` action takes two parameters: `DeviceNum`, which is the light device number from which to grab the current color; and `ProfileName`, which is the name under which to store the color. The `DeviceNum` can refer to any RGB light, not just Yeelight.

The `RestoreColorProfile` action sets a list of lights to the specified profile's color. The action takes two arguments: `DeviceList`, which is a string containing a comma-separated list of device numbers to which the named color should be set; and `ProfileName`, which is the name of the color profile. The devices listed in `DeviceList` may be any RGB light that supports the Vera-standard `urn:micasaverde-com:serviceId:Color1` service. So, it's thus possible to restore a color to a mix of lights of different types (e.g. bulbs and strips) as well as different manufacturers (e.g. Yeelight, Magiclight, Hue, etc.).

## License and Warranty

This software is provided "as-is" together with all defects, and no warranties, express or implied, are made, including but not
limited to warranties of fitness for the purpose. By using this software, you agree to assume all risks, of whatever kind, arising
in connection with your use. If you do not agree to these terms, you may not use this plugin. In any case, you may not distribute
this plugin or produce any derivative works.