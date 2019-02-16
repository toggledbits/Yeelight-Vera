--[[
    L_Yeelight1.lua - Core module for Yeelight
    Copyright 2019 Patrick H. Rigney, All Rights Reserved.
    This file is part of the Yeelight for Vera HA controllers.
--]]
--luacheck: std lua51,module,read globals luup,ignore 542 611 612 614 111/_,no max line length

module("L_Yeelight1", package.seeall)

local debugMode = false

local _PLUGIN_ID = 99999
local _PLUGIN_NAME = "Yeelight"
local _PLUGIN_VERSION = "1.1develop-19033"
local _PLUGIN_URL = "https://www.toggledbits.com/"
local _CONFIGVERSION = 000004

local math = require "math"
local string = require "string"
local socket = require "socket"
local json = require "dkjson"

local MYSID = "urn:toggledbits-com:serviceId:Yeelight1"
local MYTYPE = "urn:schemas-toggledbits-com:device:Yeelight:1"

local BULBTYPE = "urn:schemas-upnp-org:device:DimmableRGBLight:1"

local SWITCHSID = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMERSID = "urn:upnp-org:serviceId:Dimming1"
local COLORSID = "urn:micasaverde-com:serviceId:Color1"
-- local HADEVICESID = "urn:micasaverde-com:serviceId:HaDevice1"

local pluginDevice
local tickTasks = {}
local devData = {}

local runStamp = 0
local isALTUI = false
local isOpenLuup = false

local DISCOVERYPERIOD = 15

local localColors = {} -- locally defined colors are saved here

local Roscolux={ { id="0", name="clear", rgb="255,255,255" },{ id="1", name="light bastard amber", rgb="255,96,96" },{ id="2", name="bastard amber", rgb="255,192,160" },{ id="3", name="dark bastard amber", rgb="255,159,120" },{ id="4", name="medium bastard amber", rgb="253,157,125" },{ id="5", name="rose tint", rgb="254,190,209" },{ id="6", name="no color straw", rgb="253,255,215" },{ id="7", name="pale yellow", rgb="255,255,176" },{ id="8", name="pale gold", rgb="239,207,143" },{ id="9", name="pale amber gold", rgb="253,183,79" },{ id="10", name="medium yellow", rgb="255,255,32" },{ id="11", name="light straw", rgb="253,204,36" },{ id="12", name="straw", rgb="239,255,0" },{ id="13", name="straw tint", rgb="254,198,114" },{ id="14", name="medium straw", rgb="254,171,48" },{ id="15", name="deep straw", rgb="248,149,1" },{ id="16", name="light amber", rgb="255,96,0" },{ id="17", name="light flame", rgb="239,63,32" },{ id="18", name="flame", rgb="240,16,0" },{ id="19", name="fire", rgb="255,4,4" },{ id="20", name="medium amber", rgb="253,140,66" },{ id="21", name="golden amber", rgb="236,96,2" },{ id="22", name="deep amber", rgb="253,64,49" },{ id="23", name="orange", rgb="253,108,66" },{ id="24", name="scarlet", rgb="191,0,0" },{ id="25", name="orange red", rgb="255,0,0" },{ id="26", name="light red", rgb="159,0,0" },{ id="27", name="medium red", rgb="96,0,0" },{ id="30", name="light salmon pink", rgb="254,101,88" },{ id="31", name="salmon pink", rgb="254,99,134" },{ id="32", name="medium salmon pink", rgb="252,1,57" },{ id="33", name="no color pink", rgb="255,128,160" },{ id="34", name="flesh pink", rgb="255,32,64" },{ id="35", name="light pink", rgb="255,164,175" },{ id="36", name="medium pink", rgb="232,91,137" },{ id="37", name="pale rose pink", rgb="255,128,175" },{ id="38", name="light rose", rgb="255,96,175" },{ id="40", name="light salmon", rgb="255,0,0" },{ id="41", name="salmon", rgb="239,0,16" },{ id="42", name="deep salmon", rgb="144,0,0" },{ id="43", name="deep pink", rgb="255,0,112" },{ id="44", name="middle rose", rgb="223,0,112" },{ id="45", name="rose", rgb="144,0,32" },{ id="46", name="magenta", rgb="96,0,0" },{ id="47", name="light rose purple", rgb="64,0,64" },{ id="48", name="rose purple", rgb="183,2,183" },{ id="49", name="medium purple", rgb="112,0,80" },{ id="50", name="mauve", rgb="112,0,0" },{ id="51", name="surprise pink", rgb="255,128,255" },{ id="52", name="light lavender", rgb="175,16,239" },{ id="53", name="pale lavender", rgb="191,192,255" },{ id="54", name="special lavender", rgb="192,160,255" },{ id="55", name="lilac", rgb="109,79,255" },{ id="56", name="gypsy lavender", rgb="64,0,128" },{ id="57", name="lavender", rgb="64,0,128" },{ id="58", name="deep lavender", rgb="64,0,128" },{ id="59", name="indigo", rgb="48,0,80" },{ id="60", name="no color blue", rgb="128,192,255" },{ id="61", name="mist blue", rgb="80,192,208" },{ id="62", name="booster blue", rgb="80,144,191" },{ id="63", name="pale blue", rgb="16,144,191" },{ id="64", name="light steel blue", rgb="0,80,240" },{ id="65", name="daylight blue", rgb="0,64,255" },{ id="66", name="cool blue", rgb="0,192,192" },{ id="67", name="light sky blue", rgb="0,96,255" },{ id="68", name="sky blue", rgb="0,0,208" },{ id="69", name="brilliant blue", rgb="0,64,223" },{ id="70", name="nile blue", rgb="16,160,176" },{ id="71", name="sea blue", rgb="0,128,144" },{ id="72", name="azure blue", rgb="0,160,207" },{ id="73", name="peacock blue", rgb="16,144,144" },{ id="74", name="night blue", rgb="0,0,176" },{ id="76", name="light green blue", rgb="0,128,144" },{ id="77", name="green blue", rgb="0,128,223" },{ id="78", name="trudy blue", rgb="32,16,176" },{ id="79", name="bright blue", rgb="0,0,208" },{ id="80", name="primary blue", rgb="0,0,128" },{ id="81", name="urban blue", rgb="36,1,201" },{ id="82", name="surprise blue", rgb="16,0,112" },{ id="83", name="medium blue", rgb="0,0,96" },{ id="84", name="zephyr blue", rgb="30,1,163" },{ id="85", name="deep blue", rgb="0,0,96" },{ id="86", name="pea green", rgb="0,143,0" },{ id="87", name="pale yellow green", rgb="192,255,128" },{ id="88", name="light green", rgb="128,255,80" },{ id="89", name="moss green", rgb="0,122,0" },{ id="90", name="dark yellow green", rgb="16,95,0" },{ id="91", name="primary green", rgb="0,64,0" },{ id="92", name="turquoise", rgb="0,191,127" },{ id="93", name="blue green", rgb="0,176,96" },{ id="94", name="kelly green", rgb="46,135,104" },{ id="95", name="medium blue green", rgb="0,96,80" },{ id="96", name="lime", rgb="191,255,0" },{ id="97", name="light grey", rgb="192,192,192" },{ id="98", name="medium grey", rgb="112,112,112" },{ id="99", name="chocolate", rgb="144,112,96" },{ id="120", name="red diffusion", rgb="142,0,0" },{ id="121", name="blue diffusion", rgb="0,0,205" },{ id="122", name="green diffusion", rgb="0,72,0" },{ id="123", name="amber diffusion", rgb="255,45,45" },{ id="124", name="red cyc silk", rgb="151,0,0" },{ id="125", name="blue cyc silk", rgb="0,0,198" },{ id="126", name="green cyc silk", rgb="0,62,0" },{ id="127", name="amber cyc silk", rgb="255,26,26" },{ id="128", name="magenta silk", rgb="81,0,61" },{ id="129", name="sky blue silk", rgb="0,0,251" },{ id="130", name="medium blue green silk", rgb="0,89,74" },{ id="131", name="medium amber silk", rgb="253,126,0" },{ id="150", name="hamburg rose", rgb="254,203,218" },{ id="151", name="hamburg lavender", rgb="197,56,250" },{ id="152", name="hamburg steel blue", rgb="0,0,191" },{ id="304", name="pale apricot", rgb="255,160,128" },{ id="305", name="rose gold", rgb="255,128,96" },{ id="312", name="canary", rgb="252,223,90" },{ id="317", name="apricot", rgb="239,16,0" },{ id="321", name="soft golden amber", rgb="223,32,0" },{ id="337", name="true pink", rgb="255,138,197" },{ id="339", name="broadway pink", rgb="255,0,144" },{ id="342", name="rose pink", rgb="207,0,80" },{ id="344", name="follies pink", rgb="224,0,128" },{ id="355", name="pale violet", rgb="64,32,160" },{ id="356", name="middle lavender", rgb="174,53,255" },{ id="357", name="royal lavender", rgb="48,0,112" },{ id="358", name="rose indigo", rgb="32,0,80" },{ id="359", name="medium violet", rgb="16,0,96" },{ id="378", name="alice blue", rgb="80,0,208" },{ id="383", name="sapphire blue", rgb="26,0,130" },{ id="385", name="royal blue", rgb="0,0,79" },{ id="388", name="gaslight green", rgb="0,224,0" },{ id="389", name="chroma green", rgb="0,127,0" },{ id="397", name="pale grey", rgb="224,224,224" },{ id="3102", name="tough mt2", rgb="255,96,0" },{ id="3106", name="tough mty", rgb="239,63,32" },{ id="3107", name="tough y-1", rgb="253,255,215" },{ id="3114", name="tough uv filter", rgb="255,255,255" },{ id="3134", name="tough mt 54", rgb="239,207,143" },{ id="3202", name="full blue (ctb)", rgb="96,0,223" },{ id="3203", name="three-quarter blue (3/4 ctb)", rgb="0,24,136" },{ id="3204", name="half blue (1/2 ctb)", rgb="128,96,255" },{ id="3206", name="third blue (1/3 ctb)", rgb="176,176,240" },{ id="3208", name="quarter blue (1/4 ctb)", rgb="191,223,255" },{ id="3216", name="eighth blue (1/8 ctb)", rgb="223,223,223" },{ id="3220", name="double blue (2x ctb)", rgb="36,1,201" },{ id="3304", name="tough plusgreen / windowgreen", rgb="112,223,64" },{ id="3308", name="tough minusgreen", rgb="255,0,128" },{ id="3310", name="fluorofilter", rgb="255,39,28" },{ id="3313", name="tough 1/2 minusgreen", rgb="255,0,255" },{ id="3314", name="tough 1/4 minusgreen", rgb="255,128,192" },{ id="3315", name="tough 1/2 plusgreen", rgb="192,255,128" },{ id="3316", name="tough 1/4 plusgreen", rgb="203,255,151" },{ id="3317", name="tough 1/8 plusgreen", rgb="220,255,185" },{ id="3318", name="tough 1/8 minusgreen", rgb="255,128,255" },{ id="3401", name="roscosun 85", rgb="239,80,0" },{ id="3402", name="rosco n.3", rgb="192,192,192" },{ id="3403", name="rosco n.6", rgb="112,112,112" },{ id="3404", name="rosco n.9", rgb="32,32,32" },{ id="3405", name="roscosun 85n.3", rgb="144,112,96" },{ id="3406", name="roscosun 85n.6", rgb="112,80,80" },{ id="3407", name="roscosun (cto)", rgb="191,64,0" },{ id="3408", name="roscosun (1/2 cto)", rgb="255,128,0" },{ id="3409", name="roscosun (1/4 cto)", rgb="255,191,143" },{ id="3410", name="roscosun (1/8 cto)", rgb="255,224,192" },{ id="3411", name="roscosun (3/4 cto)", rgb="215,32,0" },{ id="3415", name="rosco n.15", rgb="224,224,224" },{ id="3441", name="full straw (cts)", rgb="255,96,0" },{ id="3442", name="half straw (1/2 cts)", rgb="254,198,114" },{ id="3443", name="quarter straw (1/4 cts)", rgb="239,207,143" },{ id="3444", name="eighth straw (1/8 cts)", rgb="254,232,186" },{ id="3761", name="roscolex 85", rgb="255,96,32" } }

local GamColor={ { id="105", name="antique rose", rgb="188,251,147" },{ id="106", name="1/2 antique rose", rgb="165,183,205" },{ id="107", name="1/4 antique rose", rgb="180,252,247" },{ id="108", name="1/8 antique rose", rgb="255,171,160" },{ id="110", name="dark rose", rgb="233,33,163" },{ id="120", name="bright pink", rgb="237,61,149" },{ id="130", name="rose", rgb="241,90,154" },{ id="140", name="dark magenta", rgb="185,13,164" },{ id="150", name="pink punch", rgb="192,0,96" },{ id="155", name="light pink", rgb="251,170,210" },{ id="160", name="chorus pink", rgb="252,163,209" },{ id="170", name="flesh pink", rgb="250,103,180" },{ id="180", name="cherry", rgb="249,28,94" },{ id="190", name="cold pink", rgb="252,141,174" },{ id="195", name="nymph pink", rgb="253,145,183" },{ id="220", name="pink magenta", rgb="206,4,75" },{ id="235", name="pink red", rgb="249,53,72" },{ id="245", name="light red", rgb="208,6,21" },{ id="250", name="medium red xt", rgb="116,0,16" },{ id="260", name="rosy amber", rgb="252,124,153" },{ id="270", name="red orange", rgb="111,0,0" },{ id="280", name="fire red", rgb="255,9,9" },{ id="290", name="fire orange", rgb="230,17,0" },{ id="305", name="french rose", rgb="254,150,171" },{ id="315", name="autumn glory", rgb="253,71,62" },{ id="320", name="peach", rgb="252,85,37" },{ id="323", name="indian summer", rgb="255,32,32" },{ id="325", name="bastard amber", rgb="254,173,150" },{ id="330", name="sepia", rgb="182,119,109" },{ id="335", name="coral", rgb="159,0,0" },{ id="340", name="light bastard amber", rgb="254,208,167" },{ id="343", name="honey", rgb="112,16,0" },{ id="345", name="deep amber", rgb="255,0,0" },{ id="350", name="dark amber", rgb="252,103,39" },{ id="360", name="amber blush", rgb="240,206,179" },{ id="363", name="sand", rgb="255,223,175" },{ id="364", name="pale honey", rgb="223,147,64" },{ id="365", name="warm straw", rgb="240,206,179" },{ id="370", name="spice", rgb="112,80,80" },{ id="375", name="flame", rgb="252,123,54" },{ id="380", name="golden tan", rgb="124,82,69" },{ id="385", name="light amber", rgb="253,180,136" },{ id="390", name="walnut", rgb="54,39,41" },{ id="420", name="medium amber", rgb="253,202,96" },{ id="440", name="very light straw", rgb="254,232,186" },{ id="450", name="saffron", rgb="230,157,23" },{ id="460", name="mellow yellow", rgb="248,252,82" },{ id="470", name="pale gold", rgb="239,255,57" },{ id="480", name="medium yellow", rgb="245,235,27" },{ id="510", name="no color straw", rgb="252,249,186" },{ id="520", name="new straw", rgb="198,255,167" },{ id="535", name="lime", rgb="96,255,137" },{ id="540", name="pale green", rgb="145,255,92" },{ id="570", name="light green yellow", rgb="26,226,10" },{ id="650", name="grass green", rgb="0,106,0" },{ id="655", name="rich green", rgb="0,12,0" },{ id="660", name="medium green", rgb="0,179,4" },{ id="680", name="kelly green", rgb="38,181,113" },{ id="685", name="pistachio", rgb="0,44,16" },{ id="690", name="bluegrass", rgb="0,56,32" },{ id="710", name="blue green", rgb="58,118,97" },{ id="720", name="light steel blue", rgb="119,227,255" },{ id="725", name="princess blue", rgb="0,88,112" },{ id="730", name="azure blue", rgb="0,102,123" },{ id="740", name="off blue", rgb="0,167,230" },{ id="750", name="nile blue", rgb="0,130,168" },{ id="760", name="aqua blue", rgb="34,111,119" },{ id="770", name="christel blue", rgb="47,152,164" },{ id="780", name="shark blue", rgb="54,176,190" },{ id="790", name="electric blue", rgb="104,157,255" },{ id="810", name="moon blue", rgb="0,62,176" },{ id="815", name="moody blue", rgb="0,52,108" },{ id="820", name="full light blue", rgb="147,185,255" },{ id="830", name="north sky blue", rgb="219,198,255" },{ id="835", name="aztec blue", rgb="0,0,92" },{ id="840", name="steel blue", rgb="94,0,249" },{ id="842", name="whisper blue", rgb="0,138,255" },{ id="845", name="cobalt", rgb="0,0,88" },{ id="847", name="city blue", rgb="0,0,96" },{ id="848", name="bonus blue", rgb="0,0,108" },{ id="850", name="blue (primary)", rgb="64,0,170" },{ id="860", name="sky blue", rgb="152,89,255" },{ id="870", name="winter blue", rgb="0,211,255" },{ id="880", name="daylight blue", rgb="88,0,236" },{ id="882", name="southern sky", rgb="0,28,72" },{ id="885", name="blue ice", rgb="0,132,160" },{ id="888", name="blue belle", rgb="0,24,56" },{ id="890", name="dark sky blue", rgb="2,9,136" },{ id="905", name="dark blue", rgb="0,0,108" },{ id="910", name="alice blue", rgb="16,0,100" },{ id="915", name="twilight", rgb="12,0,92" },{ id="920", name="pale lavender", rgb="241,219,255" },{ id="925", name="cosmic blue", rgb="0,0,12" },{ id="930", name="real congo blue", rgb="0,0,16" },{ id="940", name="light purple", rgb="7,26,190" },{ id="945", name="royal purple", rgb="69,2,108" },{ id="948", name="african violet", rgb="12,0,32" },{ id="950", name="purple", rgb="65,2,98" },{ id="960", name="medium lavender", rgb="138,4,210" },{ id="970", name="special lavender", rgb="175,34,251" },{ id="980", name="surprise pink", rgb="224,170,253" },{ id="990", name="dark lavender", rgb="105,4,159" },{ id="995", name="orchid", rgb="36,0,28" },{ id="1510", name="uv shield", rgb="255,255,255" },{ id="1514", name=".15 nd", rgb="199,184,189" },{ id="1515", name=".3 nd", rgb="160,160,144" },{ id="1516", name=".6 nd", rgb="116,116,116" },{ id="1517", name=".9 nd", rgb="100,100,100" },{ id="1518", name="1.2 nd", rgb="16,16,16" },{ id="1520", name="extra blue ctb", rgb="0,0,120" },{ id="1523", name="full blue ctb", rgb="0,0,96" },{ id="1526", name="3/4 blue ctb", rgb="0,24,136" },{ id="1529", name="1/2 blue ctb", rgb="20,20,220" },{ id="1532", name="1/4 blue ctb", rgb="112,160,224" },{ id="1535", name="1/8 blue ctb", rgb="104,104,217" },{ id="1540", name="extra cto", rgb="255,0,0" },{ id="1543", name="full cto", rgb="233,24,0" },{ id="1546", name="3/4 cto", rgb="215,32,0" },{ id="1549", name="1/2 cto", rgb="92,32,0" },{ id="1552", name="1/4 cto", rgb="184,88,4" },{ id="1555", name="1/8 cto", rgb="252,132,44" },{ id="1556", name="cto/.3 nd", rgb="61,30,30" },{ id="1557", name="cto/.6 nd", rgb="30,8,8" },{ id="1558", name="cto/.9 nd", rgb="16,8,8" },{ id="1560", name="y-1", rgb="225,225,92" },{ id="1565", name="mty", rgb="255,33,0" },{ id="1570", name="mt2", rgb="208,47,0" },{ id="1575", name="1/2 mt2", rgb="202,104,0" },{ id="1580", name="minusgreen", rgb="104,16,48" },{ id="1581", name="3/4 minusgreen", rgb="104,16,48" },{ id="1582", name="1/2 minusgreen", rgb="255,64,236" },{ id="1583", name="1/4 minusgreen", rgb="255,97,127" },{ id="1584", name="1/8 minusgreen", rgb="255,129,184" },{ id="1585", name="plusgreen", rgb="56,80,8" },{ id="1587", name="1/2 plusgreen", rgb="142,170,0" },{ id="1588", name="1/4 plusgreen", rgb="130,160,0" },{ id="1589", name="1/8 plusgreen", rgb="130,160,0" },{ id="1590", name="fluorofilter cw", rgb="96,0,0" } }

local Lee={ { id="2", name="rose pink", rgb="217,0,145" },{ id="3", name="lavender tint", rgb="219,177,255" },{ id="4", name="medium bastard amber", rgb="255,125,63" },{ id="7", name="pale yellow", rgb="255,255,157" },{ id="8", name="dark salmon", rgb="255,39,28" },{ id="9", name="pale amber gold", rgb="255,160,64" },{ id="10", name="medium yellow", rgb="255,220,0" },{ id="13", name="straw tint", rgb="255,181,98" },{ id="15", name="deep straw", rgb="253,130,0" },{ id="19", name="fire", rgb="252,1,7" },{ id="20", name="medium amber", rgb="255,155,106" },{ id="21", name="gold amber", rgb="253,92,15" },{ id="22", name="dark amber", rgb="223,32,32" },{ id="24", name="scarlet", rgb="223,0,0" },{ id="26", name="bright red", rgb="202,0,0" },{ id="27", name="medium red", rgb="66,0,8" },{ id="35", name="light pink", rgb="255,92,130" },{ id="36", name="mesium pink", rgb="255,98,133" },{ id="46", name="dark magenta", rgb="96,0,0" },{ id="48", name="rose purple", rgb="96,0,92" },{ id="52", name="light lavender", rgb="99,0,173" },{ id="53", name="paler lavender", rgb="162,192,255" },{ id="58", name="lavender", rgb="64,0,128" },{ id="61", name="mist blue", rgb="89,219,251" },{ id="63", name="pale blue", rgb="0,160,223" },{ id="68", name="sky blue", rgb="0,0,147" },{ id="79", name="just blue", rgb="11,11,153" },{ id="85", name="deeper blue", rgb="0,0,66" },{ id="89", name="moss green", rgb="0,159,0" },{ id="90", name="dark yellow green", rgb="4,61,0" },{ id="101", name="yellow", rgb="255,191,0" },{ id="102", name="light amber", rgb="251,210,17" },{ id="103", name="straw", rgb="255,222,181" },{ id="104", name="deep amber", rgb="249,163,34" },{ id="105", name="orange", rgb="253,121,2" },{ id="106", name="primary red", rgb="128,0,0" },{ id="107", name="light rose", rgb="255,79,109" },{ id="109", name="light salman", rgb="241,103,103" },{ id="110", name="middle rose", rgb="255,104,168" },{ id="111", name="dark pink", rgb="236,55,150" },{ id="113", name="magenta", rgb="176,0,0" },{ id="115", name="peacock blue", rgb="21,155,141" },{ id="116", name="medium blue-green", rgb="0,79,32" },{ id="117", name="steel blue", rgb="0,223,255" },{ id="118", name="light blue", rgb="17,118,255" },{ id="119", name="dark blue", rgb="0,16,128" },{ id="120", name="deep blue", rgb="35,29,118" },{ id="121", name="lee green", rgb="0,191,0" },{ id="122", name="fern green", rgb="0,232,0" },{ id="124", name="dark green", rgb="0,164,0" },{ id="126", name="mauve", rgb="96,0,112" },{ id="127", name="smokey pink", rgb="112,48,64" },{ id="128", name="bright pink", rgb="204,19,116" },{ id="129", name="heavy frost", rgb="255,255,255" },{ id="130", name="clear", rgb="255,255,255" },{ id="132", name="medium blue", rgb="0,0,192" },{ id="134", name="golden amber", rgb="254,116,69" },{ id="135", name="deep golden amber", rgb="159,34,34" },{ id="136", name="pale lavender", rgb="175,128,223" },{ id="137", name="special lavender", rgb="83,41,207" },{ id="138", name="pale green", rgb="128,255,32" },{ id="139", name="primary green", rgb="0,80,0" },{ id="141", name="bright blue", rgb="0,48,208" },{ id="142", name="pale violet", rgb="48,0,176" },{ id="143", name="pale navy blue", rgb="1,135,150" },{ id="144", name="no colour blue", rgb="0,112,223" },{ id="147", name="apricot", rgb="255,118,72" },{ id="148", name="bright rose", rgb="221,2,96" },{ id="151", name="gold tint", rgb="255,185,168" },{ id="152", name="pale gold", rgb="255,201,174" },{ id="153", name="pale salmon", rgb="255,166,184" },{ id="154", name="pale rose", rgb="255,204,191" },{ id="156", name="chocolate", rgb="120,92,92" },{ id="157", name="pink", rgb="224,0,80" },{ id="158", name="deep orange", rgb="253,94,40" },{ id="159", name="no color straw", rgb="255,255,202" },{ id="161", name="slate blue", rgb="16,48,144" },{ id="162", name="bastard amber", rgb="255,160,128" },{ id="164", name="flame red", rgb="227,0,0" },{ id="165", name="daylight blue", rgb="0,64,255" },{ id="166", name="pale red", rgb="235,3,102" },{ id="170", name="deep lavender", rgb="181,0,219" },{ id="174", name="dark steel blue", rgb="0,69,253" },{ id="176", name="loving amber", rgb="239,112,96" },{ id="179", name="chrome orange", rgb="255,125,47" },{ id="180", name="dark lavender", rgb="111,0,223" },{ id="181", name="congo blue", rgb="13,4,113" },{ id="182", name="light red", rgb="144,0,0" },{ id="183", name="moonlight blue", rgb="32,96,255" },{ id="184", name="cosmetic peach", rgb="255,239,223" },{ id="185", name="cosmetic burgundy", rgb="192,159,160" },{ id="186", name="cosmetic silver rose", rgb="255,160,207" },{ id="187", name="cosmetic rouge", rgb="255,155,134" },{ id="188", name="cosmetic highlight", rgb="255,210,200" },{ id="189", name="cosmetic silver moss", rgb="213,255,181" },{ id="190", name="cosmetic emerald", rgb="255,244,215" },{ id="191", name="cosmetic aqua blue", rgb="96,255,223" },{ id="192", name="flesh pink", rgb="223,32,96" },{ id="193", name="rosy gold", rgb="255,81,103" },{ id="194", name="surprise pink", rgb="96,64,191" },{ id="195", name="zenith blue", rgb="0,16,96" },{ id="196", name="true blue", rgb="0,64,255" },{ id="197", name="alice blue", rgb="32,64,191" },{ id="200", name="double c.t. blue", rgb="36,1,201" },{ id="201", name="full c.t. blue", rgb="0,128,255" },{ id="202", name="1/2 c.t. blue", rgb="0,128,191" },{ id="203", name="1/4 c.t. blue", rgb="215,243,255" },{ id="204", name="full c.t. orange", rgb="254,153,86" },{ id="205", name="1/2 c.t. orange", rgb="255,171,87" },{ id="206", name="1/4 c.t. orange", rgb="255,194,134" },{ id="207", name="c.t. orange +.3 nd", rgb="144,112,96" },{ id="208", name="c.t. orange +.6 nd", rgb="112,80,80" },{ id="209", name=".3 nd", rgb="192,192,192" },{ id="210", name=".6 nd", rgb="112,112,112" },{ id="211", name=".9 nd", rgb="32,32,32" },{ id="212", name="l.c.t. yellow", rgb="255,255,157" },{ id="213", name="white flame green", rgb="192,255,128" },{ id="218", name="1/8 c.t. blue", rgb="223,223,223" },{ id="219", name="lee fluorescent green", rgb="0,136,113" },{ id="223", name="1/8 c.t. orange", rgb="255,216,176" },{ id="226", name="lee u.v.", rgb="255,255,255" },{ id="230", name="super correction l.c.t. yellow", rgb="166,131,83" },{ id="232", name="super white flame", rgb="198,135,149" },{ id="236", name="h.m.i. to tungsten", rgb="255,96,0" },{ id="237", name="c.i.d. to tungsten", rgb="253,92,15" },{ id="238", name="c.s.i. to tungsten", rgb="201,67,56" },{ id="241", name="lee fluorescent 5700k", rgb="13,152,155" },{ id="242", name="lee fluorescent 4300k", rgb="50,181,135" },{ id="243", name="lee fluorescent 3600k", rgb="0,206,114" },{ id="244", name="lee plus green", rgb="112,223,64" },{ id="245", name="half plus green", rgb="192,255,128" },{ id="246", name="quarter plus green", rgb="203,255,151" },{ id="247", name="lee minus green", rgb="255,0,128" },{ id="248", name="half minus green", rgb="255,0,255" },{ id="249", name="quarter minus green", rgb="255,128,192" },{ id="278", name="eighth plus green", rgb="220,255,151" },{ id="279", name="eighth minus green", rgb="255,128,255" },{ id="281", name="3/4 c.t. blue", rgb="0,24,136" },{ id="285", name="3/4 c.t. orange", rgb="215,32,0" },{ id="298", name=".15 nd", rgb="224,224,224" },{ id="299", name="1.2 nd", rgb="16,16,16" },{ id="328", name="follies pink", rgb="204,0,43" },{ id="332", name="special rose pink", rgb="195,0,75" },{ id="343", name="special medium lavender", rgb="32,0,128" },{ id="344", name="violet", rgb="32,32,191" },{ id="353", name="lighter blue", rgb="27,136,219" },{ id="354", name="special steel blue", rgb="0,223,223" },{ id="363", name="special medium blue", rgb="0,0,96" },{ id="441", name="full c.t. straw", rgb="255,96,0" },{ id="442", name="half c.t. straw", rgb="254,198,114" },{ id="443", name="quarter c.t. straw", rgb="239,207,143" },{ id="444", name="eighth c.t. straw", rgb="254,232,186" } }

local mfgcolor = { r=Roscolux, l=Lee, g=GamColor }

local function dump(t, seen)
    if t == nil then return "nil" end
    if seen == nil then seen = {} end
    local sep = ""
    local str = "{ "
    for k,v in pairs(t) do
        local val
        if type(v) == "table" then
            if seen[v] then val = "(recursion)"
            else
                seen[v] = true
                val = dump(v, seen)
            end
        elseif type(v) == "string" then
            if #v > 255 then val = string.format("%q", v:sub(1,252).."...")
            else val = string.format("%q", v) end
        elseif type(v) == "number" and (math.abs(v-os.time()) <= 86400) then
            val = tostring(v) .. "(" .. os.date("%x.%X", v) .. ")"
        else
            val = tostring(v)
        end
        str = str .. sep .. k .. "=" .. val
        sep = ", "
    end
    str = str .. " }"
    return str
end

local function L(msg, ...) -- luacheck: ignore 212
    local str
    local level = 50
    if type(msg) == "table" then
        str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg)
        level = msg.level or level
    else
        str = _PLUGIN_NAME .. ": " .. tostring(msg)
    end
    str = string.gsub(str, "%%(%d+)", function( n )
            n = tonumber(n, 10)
            if n < 1 or n > #arg then return "nil" end
            local val = arg[n]
            if type(val) == "table" then
                return dump(val)
            elseif type(val) == "string" then
                return string.format("%q", val)
            elseif type(val) == "number" and math.abs(val-os.time()) <= 86400 then
                return tostring(val) .. "(" .. os.date("%x.%X", val) .. ")"
            end
            return tostring(val)
        end
    )
    luup.log(str, level)
end

local function D(msg, ...)
    if debugMode then
        local t = debug.getinfo( 2 )
        local pfx = _PLUGIN_NAME .. "(" .. tostring(t.name) .. "@" .. tostring(t.currentline) .. ")"
        L( { msg=msg,prefix=pfx }, ... )
    end
end

local function checkVersion(dev)
    local ui7Check = luup.variable_get(MYSID, "UI7Check", dev) or ""
    if isOpenLuup then
        return true
    end
    if luup.version_branch == 1 and luup.version_major == 7 then
        if ui7Check == "" then
            -- One-time init for UI7 or better
            luup.variable_set( MYSID, "UI7Check", "true", dev )
        end
        return true
    end
    L({level=1,msg="firmware %1 (%2.%3.%4) not compatible"}, luup.version,
        luup.version_branch, luup.version_major, luup.version_minor)
    return false
end

local function split( str, sep )
    if sep == nil then sep = "," end
    local arr = {}
    if #(str or "") == 0 then return arr, 0 end
    local rest = string.gsub( str or "", "([^" .. sep .. "]*)" .. sep, function( m ) table.insert( arr, m ) return "" end )
    table.insert( arr, rest )
    return arr, #arr
end

-- Array to map, where f(elem) returns key[,value]
local function map( arr, f, res )
    res = res or {}
    for ix,x in ipairs( arr ) do
        if f then
            local k,v = f( x, ix )
            res[k] = (v == nil) and x or v
        else
            res[x] = x
        end
    end
    return res
end

-- Initialize a variable if it does not already exist.
local function initVar( name, dflt, dev, sid )
    assert( dev ~= nil, "initVar requires dev" )
    assert( sid ~= nil, "initVar requires SID for "..name )
    local currVal = luup.variable_get( sid, name, dev )
    if currVal == nil then
        luup.variable_set( sid, name, tostring(dflt), dev )
        return tostring(dflt)
    end
    return currVal
end

-- Set variable, only if value has changed.
local function setVar( sid, name, val, dev )
    val = (val == nil) and "" or tostring(val)
    local s = luup.variable_get( sid, name, dev ) or ""
    D("setVar(%1,%2,%3,%4) old value %5", sid, name, val, dev, s )
    if s ~= val then
        luup.variable_set( sid, name, val, dev )
        return true, s
    end
    return false, s
end

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, sid )
    assert( dev ~= nil )
    assert( name ~= nil )
    assert( sid ~= nil )
    local s = luup.variable_get( sid, name, dev ) or ""
    if s == "" then return dflt end
    s = tonumber(s)
    return (s == nil) and dflt or s
end

-- Enabled?
local function isEnabled()
    return getVarNumeric( "Enabled", 1, pluginDevice, MYSID ) ~= 0
end

-- Schedule a timer tick for a future (absolute) time. If the time is sooner than
-- any currently scheduled time, the task tick is advanced; otherwise, it is
-- ignored (as the existing task will come sooner), unless repl=true, in which
-- case the existing task will be deferred until the provided time.
local function scheduleTick( tinfo, timeTick, flags )
    D("scheduleTick(%1,%2,%3)", tinfo, timeTick, flags)
    flags = flags or {}
    local function nulltick(d,p) L({level=1, "nulltick(%1,%2)"},d,p) end
    local tkey = tostring( type(tinfo) == "table" and tinfo.id or tinfo )
    assert(tkey ~= nil)
    if ( timeTick or 0 ) == 0 then
        D("scheduleTick() clearing task %1", tinfo)
        tickTasks[tkey] = nil
        return
    elseif tickTasks[tkey] then
        -- timer already set, update
        tickTasks[tkey].func = tinfo.func or tickTasks[tkey].func
        tickTasks[tkey].args = tinfo.args or tickTasks[tkey].args
        tickTasks[tkey].info = tinfo.info or tickTasks[tkey].info
        if tickTasks[tkey].when == nil or timeTick < tickTasks[tkey].when or flags.replace then
            -- Not scheduled, requested sooner than currently scheduled, or forced replacement
            tickTasks[tkey].when = timeTick
        end
        D("scheduleTick() updated %1", tickTasks[tkey])
    else
        assert(tinfo.owner ~= nil)
        assert(tinfo.func ~= nil)
        tickTasks[tkey] = { id=tostring(tinfo.id), owner=tinfo.owner, when=timeTick, func=tinfo.func or nulltick, args=tinfo.args or {},
            info=tinfo.info or "" } -- new task
        D("scheduleTick() new task %1 at %2", tinfo, timeTick)
    end
    -- If new tick is earlier than next plugin tick, reschedule
    tickTasks._plugin = tickTasks._plugin or {}
    if tickTasks._plugin.when == nil or timeTick < tickTasks._plugin.when then
        tickTasks._plugin.when = timeTick
        local delay = timeTick - os.time()
        if delay < 1 then delay = 1 end
        D("scheduleTick() rescheduling plugin tick for %1", delay)
        runStamp = runStamp + 1
        luup.call_delay( "yeelightTaskTick", delay, runStamp )
    end
    return tkey
end

-- Schedule a timer tick for after a delay (seconds). See scheduleTick above
-- for additional info.
local function scheduleDelay( tinfo, delay, flags )
    D("scheduleDelay(%1,%2,%3)", tinfo, delay, flags )
    if delay < 1 then delay = 1 end
    return scheduleTick( tinfo, delay+os.time(), flags )
end

local function gatewayStatus( m )
    setVar( MYSID, "Message", m or "", pluginDevice )
end

local function getChildDevices( typ, parent, filter )
    parent = parent or pluginDevice
    local res = {}
    for k,v in pairs(luup.devices) do
        if v.device_num_parent == parent and ( typ == nil or v.device_type == typ ) and ( filter==nil or filter(k, v) ) then
            table.insert( res, k )
        end
    end
    return res
end

local function findChildById( childId, parent )
    parent = parent or pluginDevice
    for k,v in pairs(luup.devices) do
        if v.device_num_parent == parent and v.id == childId then return k,v end
    end
    return false
end

local function findDeviceByName( name )
    name = tostring(name):lower()
    for k,v in pairs( luup.devices ) do
        if v.description:lower() == name then
            return k,v
        end
    end
    return false
end

--[[ Prep for adding new children via the luup.chdev mechanism. The existingChildren
     table (array) should contain device IDs of existing children that will be
     preserved. Any existing child not listed will be dropped. If the table is nil,
     all existing children in luup.devices will be preserved.
--]]
local function prepForNewChildren( existingChildren )
    D("prepForNewChildren(%1)", existingChildren)
    local dfMap = { [BULBTYPE]="D_DimmableRGBLight1.xml" }
    if existingChildren == nil then
        existingChildren = {}
        for k,v in pairs( luup.devices ) do
            if v.device_num_parent == pluginDevice then
                assert(dfMap[v.device_type]~=nil, "BUG: device type missing from dfMap: `"..tostring(v.device_type).."'")
                table.insert( existingChildren, k )
            end
        end
    end
    local ptr = luup.chdev.start( pluginDevice )
    for _,k in ipairs( existingChildren ) do
        local v = luup.devices[k]
        assert(v)
        assert(v.device_num_parent == pluginDevice)
        D("prepForNewChildren() appending existing child %1 (%2/%3)", v.description, k, v.id)
        luup.chdev.append( pluginDevice, ptr, v.id, v.description, "",
            dfMap[v.device_type] or error("Invalid device type in child "..k),
            "", "", false )
    end
    return ptr, existingChildren
end

local function sendDeviceCommand( cmd, params, bulb, leaveOpen )
    D("sendDeviceCommand(%1,%2,%3)", cmd, params, bulb)
    devData[tostring(bulb)].nextCmdId = ( devData[tostring(bulb)].nextCmdId or 0 ) + 1
    local pv = {}
    if type(params) == "table" then
        for k,v in ipairs(params) do
            if type(v) == "string" then
                pv[k] = string.format( "%q", v )
            else
                pv[k] = tostring( v )
            end
        end
    elseif type(params) == "string" then
        table.insert( pv, string.format( "%q", params ) )
    elseif params ~= nil then
        table.insert( pv, tostring( params ) )
    end
    local pstr = table.concat( pv, "," )
    local payload = string.format( "{ \"id\": %d, \"method\": %q, \"params\": [%s] }\r\n",
        devData[tostring(bulb)].nextCmdId, cmd or "ping", pstr )

    local s = luup.variable_get( MYSID, "Address", bulb ) or ""
    local addr,port = s:match("^([^:]+):(%d+)")
    if addr == nil then addr = s port = 55443 end

    D("sendDeviceCommand() sending payload %1 to %2:%3", payload, addr, port)
    local sock = socket.tcp()
    sock:settimeout( 5 )
    if not sock:connect( addr, tonumber(port) or 55443 ) then
        L({level=2,msg="%1 (%2) connection failed to %4:%5, can't %3"}, luup.devices[bulb].description,
            bulb, cmd, addr, port)
        luup.set_failure( 1, bulb )
        sock:close()
        return
    end
    sock:settimeout( 1 )
    sock:send( payload )
    luup.set_failure( 0, bulb )
    if leaveOpen then
        return sock
    end
    sock:close()
    scheduleDelay( tostring(bulb), 2 )
    return false
end

-- Decode color to Vera-style. -ish. If the color spec starts with "!", then
-- see if we're Roscolux or Lee, and try to map.
local function decodeColor( color )
    local newColor = tostring( color or "" ):lower()
    if localColors[newColor] then return localColors[newColor] end
    local name
    local mfg,num = newColor:match( "^([a-z])(%d+)" )
    if not mfg then
        mfg,name = newColor:match( "^([a-z])(.*)" )
    end
    D("decodeColor() got mfg=%1 id=%2 name=%3", mfg, num, name)
    if not mfg then return color end -- No good, just return what we got.
    local t = mfgcolor[mfg]
    if t then
        for _,v in ipairs( t ) do
            if name and v.name == name then return v.rgb end
            if v.id == num then return v.rgb end
        end
    else
        L({level=2,msg="SetColor can't find manufacturer table for %1"}, color)
        return false
    end
    -- No luck.
    return false
end

-- Approximate RGB from color temperature. We don't both with most of the algorithm
-- linked below because the lower limit is 2000 (Vera) and the upper is 6500 (Yeelight).
-- We're also not going nuts with precision, since the only reason we're doing this is
-- to make the color spot on the UI look somewhat sensible when in temperature mode.
-- Ref: https://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
local function approximateRGB( t )
    local function bound( v ) if v < 0 then v=0 elseif v > 255 then v=255 end return math.floor(v) end
    local r,g,b = 255
    t = t / 100
    g = bound( 99.471 * math.log(t) - 161.120 )
    b = bound( 138.518 * math.log(t-10) - 305.048 )
    return r,g,b
end

local checkBulb -- forward decl
local function checkBulbProp( bulb, taskid, argv )
    D("checkBulbProp(%1,%2,%3)", bulb, taskid, argv)
    local sock, startTime = unpack( argv )
    sock:settimeout( 0 )
    local changed = false
    while true do
        local p, err, part = sock:receive()
        if p then
            D("checkBulbProp() handling response data: %1", p)
            local data = json.decode( p )
            if data and data.result and type(data.result) == "table" then
                changed = changed or setVar( SWITCHSID, "Status", (data.result[1]=="on") and 1 or 0, bulb )
                changed = changed or setVar( SWITCHSID, "Target", (data.result[1]=="on") and 1 or 0, bulb )
                changed = changed or setVar( DIMMERSID, "LoadLevelStatus", (data.result[1]=="on") and data.result[2] or 0, bulb )
                changed = changed or setVar( DIMMERSID, "LoadLevelTarget", (data.result[1]=="on") and data.result[2] or 0, bulb )
                local w,d,r,g,b = 0,0,0,0,0
                if data.result[5] == "1" then
                    -- Light in RGB mode
                    local v = tonumber( data.result[4] ) or 0
                    r = math.floor( v / 65536 )
                    g = math.floor( v / 256 ) % 256
                    b = v % 256
                    setVar( MYSID, "HexColor", string.format("%02x%02x%02x", r, g, b), bulb )
                elseif data.result[5] == "2" then
                    -- Light in color temp mode
                    local v = tonumber( data.result[3] ) or 3000
                    if v >= 5500 then
                        -- Daylight (cool) range
                        d = math.floor( ( v - 5500 ) / 3500 * 255 )
                    else
                        -- Warm range
                        w = math.floor( ( v - 2000 ) / 3500 * 255 )
                    end
                    r,g,b = approximateRGB( v )
                    setVar( MYSID, "HexColor", string.format("%02x%02x%02x", r, g, b), bulb )
                    r,g,b = 0,0,0
                end -- 3=HSV, we don't support
                changed = changed or setVar( COLORSID, "CurrentColor", string.format( "0=%d,1=%d,2=%d,3=%d,4=%d", w, d, r, g, b ), bulb )
                local targetColor = string.format( "0=%d,1=%d,2=%d,3=%d,4=%d", w, d, r, g, b )
                changed = changed or setVar( COLORSID, "TargetColor", targetColor, bulb )

                if getVarNumeric( "AuthoritativeForDevice", 0, bulb, MYSID ) ~= 0 then
                    -- ??? to do
                end

                break
            elseif data and data.method and data.method == "props" then
                -- Notification message in response to another command.
                -- Ignore it and keep going.
            else
                L({level=2,msg="%1 (%2) malformed property response from bulb"},
                    luup.devices[bulb].description, bulb)
                luup.log( p, 2 )
            end
        elseif err ~= "timeout" then
            D("checkBulbProp() socket error %1 part %2, closing", err, part)
            break
        elseif os.time() < (startTime + 5) then
            D("checkBulbProp() %1 part %2, continuing...", err, part)
            scheduleDelay( taskid, 1 )
            return
        else
            -- Time expired waiting for response.
            break
        end
    end
    -- Terminate read cycle
    D("checkBulbProp() closing socket, ending prop update; changed=%1", changed)
    sock:close()
    local updateInterval = getVarNumeric( "UpdateInterval", getVarNumeric( "UpdateInterval", 120, pluginDevice, MYSID ), bulb, MYSID )
    if changed then updateInterval = 2 end
    scheduleDelay( { id=taskid, info="check", owner=bulb, func=checkBulb, args={} }, updateInterval )
end

checkBulb = function( bulb, taskid )
    D("checkBulb(%1)", bulb)
    local sock = sendDeviceCommand( "get_prop", { "power", "bright", "ct", "rgb", "color_mode" }, bulb, true )
    if sock then
        scheduleDelay( { id=taskid, info="readprop", func=checkBulbProp, args={ sock, os.time() } }, 1 )
        return
    end
    local updateInterval = getVarNumeric( "UpdateInterval", getVarNumeric( "UpdateInterval", 120, pluginDevice, MYSID ), bulb, MYSID )
    scheduleDelay( { id=taskid, info="check", owner=bulb, func=checkBulb, args={} }, updateInterval )
end

-- One-time init for bulb
local function initBulb( bulb )
    D("initBulb(%1)", bulb)
    local s = getVarNumeric( "Version", 0, bulb, MYSID )
    if s == 0 then
        -- First-time initialization
        -- initVar( "Address", "", bulb, MYSID ) -- set by child creation
        initVar( "UpdateInterval", "", bulb, MYSID )
        initVar( "HexColor", "808080", bulb, MYSID )
        initVar( "AuthoritativeForDevice", "0", bulb, MYSID )

        initVar( "Target", "0", bulb, SWITCHSID )
        initVar( "Status", "-1", bulb, SWITCHSID )

        initVar( "LoadLevelTarget", "0", bulb, DIMMERSID )
        initVar( "LoadLevelStatus", "0", bulb, DIMMERSID )
        initVar( "LoadLevelLast", "100", bulb, DIMMERSID )
        initVar( "TurnOnBeforeDim", "0", bulb, DIMMERSID )
        initVar( "AllowZeroLevel", "0", bulb, DIMMERSID )

        initVar( "TargetColor", "0=51,1=0,2=0,3=0,4=0", bulb, COLORSID )
        initVar( "CurrentColor", "", bulb, COLORSID )
        
        luup.attr_set( "category_num", "2", bulb )
        luup.attr_set( "subcategory_num", "4", bulb )
        luup.attr_set( "device_json", "D_YeelightRGBLight1.json", bulb )
        
        luup.variable_set( MYSID, "Version", _CONFIGVERSION, bulb ) -- force
        
        return true -- signal reload required for changes made.
    end
    
    if s < 000004 then
        luup.attr_set( "category_num", "2", bulb )
        luup.attr_set( "subcategory_num", "4", bulb )
        luup.attr_set( "device_json", "D_YeelightRGBLight1.json", bulb )
        luup.variable_set( MYSID, "Version", _CONFIGVERSION, bulb ) -- force
        return true -- signal reload requires for changes made
    end

    setVar( MYSID, "Version", _CONFIGVERSION, bulb )
    return false -- no reload required for changes made
end

-- Start bulb
local function startBulb( bulb )
    D("startBulb(%1)", bulb)

    devData[tostring(bulb)] = {}

    scheduleDelay( { id=tostring(bulb), info="check", owner=bulb, func=checkBulb }, 2 )
end

-- Check bulbs
local function startBulbs( dev )
    D("startBulbs(%1)",dev)
    local bulbs = getChildDevices( BULBTYPE, dev )
    local needReload = false
    for _,bulb in ipairs( bulbs ) do
        if initBulb( bulb ) then 
            needReload = true
        end
        
        startBulb( bulb )
    end
    if needReload then 
        L{level=2,msg="Bulb configuration(s) updated; Luup reload required now..."}
        luup.sleep(5000) -- The only place I would ever do this
        luup.reload()
    end
    return #bulbs
end

--[[
    D I S C O V E R Y   A N D   C O N N E C T I O N
--]]

-- Process discovery responses
local function processDiscoveryResponses( dev )
    D("processDiscoveryResponses(%1)", dev)
    gatewayStatus("Processing discovery results")
    local ptr,existing = prepForNewChildren()
    local seen = map( existing, function( n ) return luup.devices[n].id end )
    local hasNew = false
    for _,ndev in pairs(devData[tostring(dev)].discoveryResponses) do
        local newid = ndev.Id
        if not seen[newid] then
            L("Adding new device %1 found at %2...", newid, ndev.Address)
            local sv = { MYSID .. ",Address=" .. ndev.Address }
            if ndev.Info then
                if ndev.Info.model then table.insert( sv, MYSID .. ",Model="..ndev.Info.model ) end
                if ndev.Info.support then table.insert( sv, MYSID .. ",Supports="..ndev.Info.support ) end
            end
            luup.chdev.append( pluginDevice, ptr,
                newid, -- id (altid)
                ndev.Name, -- description
                BULBTYPE, -- device type
                "D_DimmableRGBLight1.xml", -- device file
                "", -- impl file
                table.concat( sv, "\n" ), -- state vars
                false -- embedded
            )
            hasNew = true
        else
            -- Existing device; update address.
            L("Updating IP for existing device %1 (%2 #%3) to %4", newid,
                (luup.devices[seen[newid]] or {}).description, seen[newid], ndev.Address)
            luup.variable_set( MYSID, "Address", ndev.Address, seen[newid] )
        end
    end

    -- Close children. This will cause a Luup reload if something changed.
    if hasNew then
        L("New bulb(s) added, Luup reload coming!")
        gatewayStatus("New device(s) created, reloading Luup...")
        luup.sleep(5000) -- The only time I would ever do this (before sync)
    else
        L("No new devices discovered.")
        gatewayStatus("No new devices discovered.")
    end
    luup.chdev.sync( pluginDevice, ptr )
end

-- Handle discovery message
local function handleDiscoveryResponse( response, dev )
    D("handleDiscoveryResponse(%1,%2)", response, dev)

    local addr,port = tostring( response or "" ):lower():match( "location: *yeelight://([^:]+):(%d+)" )
    if addr then
        -- Parse the response headers.
        local r = split( response, "[\r\n]+" )
        local rf = {}
        for _,v in ipairs( r or {} ) do
            local hh,hv = string.match( v, "^([^:]+): *(.*)" )
            if hh then
                rf[hh:lower()] = hv
            end
        end
        if ( rf.id or "" ) ~= "" then
            local id = rf.id:lower():gsub( "^0x", "" )
            local name = ( rf.name or "" ) ~= "" and rf.name or ( "yeelight-" .. id:gsub( "^0+", "" ) )
            L("Received discovery response from %1 at %2", id, addr)

            -- Store it.
            devData[tostring(dev)].discoveryResponses = devData[tostring(dev)].discoveryResponses or {}
            if devData[tostring(dev)].discoveryResponses[id] == nil then
                devData[tostring(dev)].discoveryResponses[id] = { Id=id, Name=name or id, Address=addr .. ":" .. port, Info=rf }
            end
        else
            L({level=2,msg="Skipping discovered device at %1 because it did not provide ID"}, addr)
        end
    else
        D("handleDiscoveryResponse() ignoring non-compliant response: %1", response)
    end
end

-- Tick for SSDP discovery.
local function SSDPDiscoveryTask( dev, taskid )
    D("SSDPDiscoveryTask(%1,%2)", dev, taskid)

    local rem = math.max( 0, devData[tostring(dev)].discoveryTime - os.time() )
    gatewayStatus( string.format( "Discovery running (%d%%)...",
        math.floor((DISCOVERYPERIOD-rem)/DISCOVERYPERIOD*100)) )

    local udp = devData[tostring(dev)].discoverySocket
    if udp ~= nil then
        repeat
            udp:settimeout( 1 )
            local resp, peer, port = udp:receivefrom()
            if resp ~= nil then
                D("SSDPDiscoveryTask() received response from %1:%2", peer, port)
                if string.find( resp, "^M-SEARCH" ) then
                    -- Huh. There's an echo.
                else
                    handleDiscoveryResponse( resp, dev )
                end
            end
        until resp == nil

        D("SSDPDiscoveryTask() no more data")
        if os.time() < devData[tostring(dev)].discoveryTime then
            scheduleDelay( taskid, 1 )
            return
        else
            scheduleTick( taskid, 0 ) -- remove task
        end
        udp:close()
        devData[tostring(dev)].discoverySocket = nil
        devData[tostring(dev)].discoveryTime = nil
    end
    D("SSDPDiscoveryTask() end of discovery")
    processDiscoveryResponses( dev )
end

-- Launch SSDP discovery.
local function launchSSDPDiscovery( dev )
    D("launchSSDPDiscovery(%1)", dev)
    assert(dev ~= nil)
    assert(luup.devices[dev].device_type == MYTYPE, "Discovery much be launched with gateway device")

    -- Configure
    local addr = "239.255.255.250"
    local port = 1982
    local payload = string.format(
        "M-SEARCH * HTTP/1.1\r\nHOST: %s:%d\r\nMAN: \"ssdp:discover\"\r\nST: wifi_bulb\r\n\r\n",
        addr, port)

    -- Any of this can fail, and it's OK.
    local udp = socket.udp()
    udp:setsockname('*', port)
    D("launchSSDPDiscovery() sending discovery request %1", payload)
    local stat,err = udp:sendto( payload, addr, port)
    if stat == nil then
        gatewayStatus("Discovery failed! " .. tostring(err))
        L("Failed to send discovery req: %1", err)
        return
    end

    devData[tostring(dev)].discoverySocket = udp
    local now = os.time()
    devData[tostring(dev)].discoveryTime = now + DISCOVERYPERIOD
    devData[tostring(dev)].discoveryResponses = {}

    scheduleDelay( { id="discovery-"..dev, func=SSDPDiscoveryTask, owner=dev }, 1 )
    gatewayStatus( "Discovery running..." )
end

--[[
    ***************************************************************************
    A C T I O N   I M P L E M E N T A T I O N
    ***************************************************************************
--]]

-- Toggle state
function actionToggleState( bulb )
    assert(luup.devices[bulb].device_type == BULBTYPE)
    sendDeviceCommand( "toggle", nil, bulb )
end

-- Save current bulb settings as default power-on setting.
function actionSetDefault( bulb )
    assert(luup.devices[bulb].device_type == BULBTYPE)
    sendDeviceCommand( "set_default", nil, bulb )
end

function actionPower( state, dev )
    assert(luup.devices[dev].device_type == BULBTYPE)
    -- Switch on/off
    if type(state) == "string" then state = ( tonumber(state) or 0 ) ~= 0
    elseif type(state) == "number" then state = state ~= 0 end
    sendDeviceCommand( "set_power", { state and "on" or "off", "smooth", 500 }, dev )
    setVar( SWITCHSID, "Target", state and "1" or "0", dev )
    setVar( SWITCHSID, "Status", state and "1" or "0", dev )
    -- UI needs LoadLevelTarget/Status to comport with state according to Vera's rules.
    if not state then
        setVar( DIMMERSID, "LoadLevelTarget", 0, dev )
        setVar( DIMMERSID, "LoadLevelStatus", 0, dev )
    else
        -- Restore brightness
        local bright = getVarNumeric( "LoadLevelLast", 0, dev, DIMMERSID )
        if bright > 0 then
           sendDeviceCommand( "set_bright", { bright, "smooth", 500 }, dev )
        end
    end
end

function actionBrightness( newVal, dev )
    assert(luup.devices[dev].device_type == BULBTYPE)
    -- Dimming level change
    newVal = tonumber( newVal ) or 100
    if newVal < 0 then newVal = 0 elseif newVal > 100 then newVal = 100 end -- range
    if newVal > 0 then
        -- Level > 0, if light is off, turn it on.
        local status = getVarNumeric( "Status", 0, dev, SWITCHSID )
        if status == 0 then
            sendDeviceCommand( "set_power", { "on", "smooth", 500 }, dev )
            setVar( SWITCHSID, "Target", 1, dev )
            setVar( SWITCHSID, "Status", 1, dev )
        end
        sendDeviceCommand( "set_bright", { newVal, "smooth", 500 }, dev )
    elseif getVarNumeric( "AllowZeroLevel", 0, dev, DIMMERSID ) ~= 0 then
        -- Level 0 allowed as on state, just go with it.
        sendDeviceCommand( "set_bright", { 0, "smooth", 500 }, dev )
    else
        -- Level 0 (not allowed as an "on" state), switch light off.
        sendDeviceCommand( "set_power", { "off", "smooth", 500 }, dev )
        setVar( SWITCHSID, "Target", 0, dev )
        setVar( SWITCHSID, "Status", 0, dev )
    end
    setVar( DIMMERSID, "LoadLevelTarget", newVal, dev )
    setVar( DIMMERSID, "LoadLevelStatus", newVal, dev )
    if newVal > 0 then
        setVar( DIMMERSID, "LoadLevelLast", newVal, dev )
    end
end

function actionSetColor( newVal, dev )
    D("actionSetColor(%1,%2)", newVal, dev)
    assert(luup.devices[dev].device_type == BULBTYPE)
    if string.match( tostring(newVal), "!" ) then
        newVal = newVal:sub(2)
        local t = decodeColor( newVal )
        if t == newVal then L({level=2,msg="SetColor lookup for !%1 failed"}, newVal)
        else
            L("SetColor lookup for !%1 returns RGB %2", newVal, t)
            newVal = t
        end
    end
    local targetColor = newVal
    local status = getVarNumeric( "Status", 0, dev, SWITCHSID )
    if status == 0 then
        sendDeviceCommand( "set_power", { "on", "smooth", 500 }, dev )
        setVar( SWITCHSID, "Target", 1, dev )
        setVar( SWITCHSID, "Status", 1, dev )
    end
    local w, c, r, g, b
    local s = split( newVal )
    if #s == 3 then
        -- R,G,B
        r = tonumber(s[1])
        g = tonumber(s[2])
        b = tonumber(s[3])
        w, c = 0, 0
        local rgb = r * 65536 + g * 256 + b
        sendDeviceCommand( "set_rgb", { rgb, "smooth", 500 }, dev )
    else
        -- Wnnn, Dnnn (color range)
        local yeemin = getVarNumeric( "MinTemperature", 1600, dev, MYSID )
        local yeemax = getVarNumeric( "MaxTemperature", 6500, dev, MYSID )
        local code,temp = newVal:upper():match( "([WD])(%d+)" )
        local t
        if code == "W" then
            t = tonumber(temp) or 128
            temp = 2000 + math.floor( t * 3500 / 255 )
            if temp < yeemin then temp = yeemin elseif temp > yeemax then temp = yeemax end
            w = t 
            c = 0
        elseif code == "D" then
            t = tonumber(temp) or 128
            temp = 5500 + math.floor( t * 3500 / 255 )
            if temp < yeemin then temp = yeemin elseif temp > yeemax then temp = yeemax end
            c = t
            w = 0
        elseif code == nil then
            -- Try to evaluate as integer (2000-9000K)
            temp = tonumber(newVal) or 2700
            if temp < yeemin then temp = yeemin elseif temp > yeemax then temp = yeemax end
            if temp <= 5500 then
                if temp < 2000 then temp = 2000 end -- enforce Vera min
                w = math.floor( ( temp - 2000 ) / 3500 * 255 )
                c = 0
                targetColor = string.format("W%d", w)
            elseif temp > 5500 then
                if temp > 9000 then temp = 9000 end -- enforce Vera max
                c = math.floor( ( temp - 5500 ) / 3500 * 255 )
                w = 0
                targetColor = string.format("D%d", c)
            else
                L({level=1,msg="Unable to set color, target value %1 invalid"}, newVal)
                return
            end
        end
        sendDeviceCommand( "set_ct_abx", { temp, "smooth", 500 }, dev )
        r,g,b = approximateRGB( temp )
    end

    --[[
    -- Well this is... bizarre.
    local cc = string.format("0=%d,1=%d,2=%d,3=%d,4=%d", w, c, r, g, b)
    D("actionSetColor() newVal %1, new CurrentColor %2", newVal, cc)
    setVar( COLORSID, "TargetColor", cc, dev )
    setVar( COLORSID, "CurrentColor", cc, dev )
    setVar( MYSID, "HexColor", string.format("%02x%02x%02x", r, g, b), dev )
    --]]
end

function actionSaveColorProfile( rgb, name, dev )
    D("actionSaveColorProfile(%1,%2,%3)", rgb, name, dev)
    local r,g,b = 0,0,0
    rgb = rgb or ""
    if rgb == "" then
        -- Empty RGB means delete profile
    else
        r,g,b = rgb:match( "^(%d+),(%d+),(%d+)$" )
        if not r then
            r,g,b = rgb:match( "^#?(%x%x)(%x%x)(%x%x)$" )
            if not r then
                L({level=1,msg="SaveColorProfile failed, invalid RGB string %1; must be r,g,b (0-255 each) or rrggbb (00-FF each)"}, rgb)
            end
            r = tonumber( r, 16 ) or 0
            g = tonumber( g, 16 ) or 0
            b = tonumber( b, 16 ) or 0
        else
            r = tonumber( r ) or 0
            g = tonumber( g ) or 0
            b = tonumber( b ) or 0
        end
    end
    localColors[tostring(name or ""):lower()] = (rgb == "") and nil or string.format("%d,%d,%d", r, g, b)
    D("actionSaveColorProfile() profiles now %1", localColors )
    luup.variable_set( MYSID, "LocalColorProfiles", json.encode( localColors ), dev )
end

-- This function is device agnostic and will work on any light that implements
-- the Color1 service.
function actionSaveCurrentColor( light, name, dev )
    D("actionSaveCurrentColor(%1,%2,%3)", light, name, dev)
    local n = tonumber( light )
    if n == nil then
        n = findDeviceByName( light )
    end
    if not ( n and luup.devices[n] ) then
        L({level=1,msg="SaveCurrentColor failed, device %1 not found"}, light)
    elseif not luup.device_supports_service( COLORSID, n ) then
        L({level=1,msg="SaveCurrentColor failed, device %1 does not support service %2"}, light, COLORSID)
        return
    end

    local cc = luup.variable_get( COLORSID, "CurrentColor", n )
    cc = split( cc )
    if #cc == 5 then
        -- Remove first two elements (color temps we no longer need)
        table.remove( cc, 1 )
        table.remove( cc, 1 )
        for k,v in ipairs( cc ) do
            cc[k] = v:match("%d+=(%d+)")
        end
        D("actionSaveCurrentColor() saving profile %1 as %2", name, cc)
        localColors[tostring(name or ""):lower()] = table.concat( cc, "," )
        luup.variable_set( MYSID, "LocalColorProfiles", json.encode( localColors ), dev )
        return
    end
    L({level=1,msg="SaveCurrentColor failed, current color not available for %1"}, n)
end

-- This function is device agnostic and will work on any light that implements
-- the Color1 service.
function jobRestoreColorProfile( light, name, dev )
    D("jobRestoreColorProfile(%1,%2,%3)", light, name, dev)
    name = name:gsub( "^%!", "" )
    local t = decodeColor( name )
    if not t then
        L({level=1,msg="RestoreColorProfile failed, profile %1 not found"}, name)
        return 2,0 -- this is fatal
    end
    local list = split( light )
    for _,d in ipairs( list or {} ) do
        local n = tonumber(d)
        if n == nil then
            local ld = d:lower()
            for k,v in pairs( luup.devices ) do
                if v.description:lower() == ld then
                    n = k
                    break
                end
            end
        end
        if not ( n and luup.devices[n] ) then
            L({level=2,msg="RestoreColorProfile ignoring %1, invalid device number"}, d)
        elseif not luup.device_supports_service( COLORSID, n ) then
            L({level=2,msg="RestoreColorProfile ignoring %1, does not support service %2"}, n, COLORSID)
        else
            luup.call_action( COLORSID, "SetColorRGB", { newColorRGBTarget=t }, n )
        end
    end
    return 4,0
end

function actionGetColorProfile( name, dev )
    D("actionGetColorProfile(%1,%2)", name, dev)
    name = name:gsub( "^%!", "" )
    local temp = decodeColor( name ) or ""
    luup.variable_set( MYSID, "X_getprofileresult", temp, dev )
    D("actionGetColorProfile() returning %1 for %2", temp, name)
    return temp
end

function jobSetGroup( groupId, groupName, groupMembers, dev )
    local groupDev = findChildById( groupId )
    if not groupDev then
        local ptr = prepForNewChildren()
        luup.chdev.append( dev, ptr, groupId, groupName or ("Group "..groupId), "",
            "D_DimmableRGBLight1.xml", "",
            MYSID .. ",GroupMembers=" .. groupMembers, false )
        luup.chdev.sync( dev, ptr )
    else
        luup.attr_set( "name", groupName, groupDev )
        luup.variable_set( MYSID, "GroupMembers", groupMembers, groupDev )
    end
    return 4,0
end

-- Run Yeelight discovery
function jobRunDiscovery( pdev )
    if false and isOpenLuup then
        gatewayStatus( "SSDP discovery not available on openLuup; use IP discovery" )
        return 2,0
    end
    launchSSDPDiscovery( pdev )
    return 4,0
end

-- IP discovery. Connect/query, and if we succeed, add.
function jobDiscoverIP( pdev, target )
    if devData[tostring(pdev)].discoverySocket then
        L{level=2,msg="SSDP discovery running, can't do direct IP discovery"}
        return 2,0
    end
    -- Clean and canonicalize
    target = string.gsub( string.gsub( tostring(target or ""), "^%s+", "" ), "%s+$", "" )
    D("jobDiscoverIP() checking %1", target)
    local addr,port = string.match( target, "^([^:]+):(%d+)" )
    if not addr then
        port = 55443
        addr = target
    else
        port = tonumber(port)
    end
    if not (addr and port) then
        gatewayStatus("Discovery IP invalid, must be A.B.C.D:port")
        return 2,0
    end
    L("Attempting direct IP discovery at %1:%2", addr, port)
    gatewayStatus("Contacting " .. addr)
    local sock = socket.tcp()
    if sock:connect( addr, port ) then
        D("jobDiscoverIP() connected, sending get_prop to %1:%2", addr, port)
        sock:send("{ \"id\": 1, \"method\": \"get_prop\", \"params\": [ \"power\",\"id\",\"name\" ] }\r\n")
        sock:settimeout(5)
        local r,err = sock:receive()
        if r then
            D("jobDiscoverIP() got direct discovery response: %1", r)
            sock:close()
            local data = json.decode( r )
            if data and data.result then
                -- Looks real enough. We don't have an ID, so generate one.
                local pfx = string.char( 96 + math.random( 26 ) )
                local id = string.format( "%s%x", pfx, math.floor( socket.gettime() * 10 ) % (2^31-2) )
                local name = "yeelight-" .. id
                gatewayStatus("Registering "..name)
                devData[tostring(pdev)].discoveryResponses = { [id]={ Id=id, Name=name, Address=addr..":"..port, Info={} } }
                processDiscoveryResponses( pdev )
                return 4,0
            end
        else
            D("jobDiscoverIP() receive error: %1", err)
            gatewayStatus("Invalid or no response from device at "..addr..":"..port)
        end
    else
        D("jobDiscoverIP() could not connect to %1:%2", addr, port)
        gatewayStatus("Can't connect to "..addr..":"..port)
    end
    sock:close()
    return 2,0
end

-- Enable or disable debug
function actionSetDebug( state, tdev )
    assert(tdev == pluginDevice) -- on master only
    if string.find( ":debug:true:t:yes:y:1:", string.lower(tostring(state)) ) then
        debugMode = true
    else
        local n = tonumber(state or "0") or 0
        debugMode = n ~= 0
    end
    if debugMode then
        D("Debug enabled")
    end
end

-- Dangerous debug stuff. Remove all child devices except bulbs.
function actionMasterClear( dev )
    assert( luup.devices[dev].device_type == MYTYPE )
    gatewayStatus( "Clearing children..." )
    local ptr = luup.chdev.start( pluginDevice )
    luup.sleep(5000) -- I would only ever do this here.
    luup.chdev.sync( pluginDevice, ptr )
end

--[[
    ***************************************************************************
    P L U G I N   B A S E
    ***************************************************************************
--]]
-- plugin_runOnce() looks to see if a core state variable exists; if not, a
-- one-time initialization takes place.
local function plugin_runOnce( pdev )
    local s = getVarNumeric("Version", 0, pdev, MYSID)
    if s ~= 0 and s == _CONFIGVERSION then
        -- Up to date.
        return
    elseif s == 0 then
        L("First run, setting up new plugin instance...")
        initVar( "Message", "", pdev, MYSID )
        initVar( "Enabled", "1", pdev, MYSID )
        initVar( "LocalColorProfiles", "{}", pdev, MYSID )
        initVar( "DebugMode", 0, pdev, MYSID )
        initVar( "DiscoveryBroadcast", "", pdev, MYSID )
        initVar( "UpdateInterval", "", pdev, MYSID )

        luup.attr_set('category_num', 1, pdev)

        luup.variable_set( MYSID, "Version", _CONFIGVERSION, pdev )
        return
    end

    -- Consider per-version changes.
    if s < 000003 then
        initVar( "LocalColorProfiles", "{}", pdev )
    end

    -- Update version last.
    if s ~= _CONFIGVERSION then
        luup.variable_set( MYSID, "Version", _CONFIGVERSION, pdev )
    end
end

-- Tick handler for master device
local function masterTick(pdev,taskid)
    D("masterTick(%1,%2)", pdev,taskid)
    assert(pdev == pluginDevice)
    -- Set default time for next master tick
    -- local nextTick = math.floor( os.time() / 60 + 1 ) * 60

    -- Do master tick work here

    -- Schedule next master tick.
    -- This plugin doesn't need one, so we let it die.
    -- scheduleTick( taskid, nextTick )
end

-- Start plugin running.
function startPlugin( pdev )
    L("plugin version %2 master device %3 (#%1)", pdev, _PLUGIN_VERSION, luup.devices[pdev].description)

    luup.variable_set( MYSID, "Message", "Initializing...", pdev )

    -- Early inits
    pluginDevice = pdev
    isALTUI = false
    isOpenLuup = false
    tickTasks = {}
    devData[tostring(pdev)] = {}

    math.randomseed( os.time() )

    -- Debug?
    if getVarNumeric( "DebugMode", 0, pdev, MYSID ) ~= 0 then
        debugMode = true
        D("startPlugin() debug enabled by state variable DebugMode")
    end

    -- Check for ALTUI and OpenLuup
    local failmsg = false
    for k,v in pairs(luup.devices) do
        if v.device_type == "urn:schemas-upnp-org:device:altui:1" and v.device_num_parent == 0 then
            D("start() detected ALTUI at %1", k)
            isALTUI = true
            --[[
            local rc,rs,jj,ra = luup.call_action("urn:upnp-org:serviceId:altui1", "RegisterPlugin",
                {
                    newDeviceType=MYTYPE,
                    newScriptFile="",
                    newDeviceDrawFunc="",
                    newStyleFunc=""
                }, k )
            D("startSensor() ALTUI's RegisterPlugin action for %5 returned resultCode=%1, resultString=%2, job=%3, returnArguments=%4", rc,rs,jj,ra, MYTYPE)
            --]]
        elseif v.device_type == "openLuup" then
            D("start() detected openLuup")
            isOpenLuup = true
        end
    end
    if failmsg then
        return false, failmsg, _PLUGIN_NAME
    end

    -- Check UI version
    if not checkVersion( pdev ) then
        L({level=1,msg="This plugin does not run on this firmware."})
        luup.variable_set( MYSID, "Message", "Unsupported firmware "..tostring(luup.version), pdev )
        luup.set_failure( 1, pdev )
        return false, "Incompatible firmware " .. luup.version, _PLUGIN_NAME
    end

    -- One-time stuff
    plugin_runOnce( pdev )

    -- More inits
    local enabled = isEnabled( pdev )
    for _,d in ipairs( getChildDevices( nil, pdev ) or {} ) do
        luup.attr_set( 'invisible', enabled and 0 or 1, d )
    end
    luup.attr_set( 'invisible', 0, pdev )
    if not enabled then
        L{level=2,msg="disabled (see Enabled state variable)"}
        gatewayStatus("DISABLED")
        return true, "Disabled", _PLUGIN_NAME
    end

    -- Initialize and start the plugin timer and master tick
    runStamp = 1
    scheduleDelay( { id="master", func=masterTick, owner=pdev }, 5 )
    local s = luup.variable_get( MYSID, "LocalColorProfiles", pdev ) or ""
    localColors = json.decode( s ) or {}
    luup.variable_watch( 'yeelightWatchCallback', MYSID, "LocalColorProfiles", pdev )

    -- Start bulbs
    local count = startBulbs( pdev )

    -- Return success
    gatewayStatus( "Managing " .. count .. " light" .. ( count == 1 and "" or "s" ) )
    luup.set_failure( 0, pdev )
    return true, "Ready", _PLUGIN_NAME
end

-- Plugin timer tick. Using the tickTasks table, we keep track of tasks that
-- need to be run and when, and try to stay on schedule. This keeps us light on
-- resources: typically one system timer only for any number of devices.
local functions = { [tostring(masterTick)]="masterTick", [tostring(checkBulb)]="checkBulb", [tostring(checkBulbProp)]="checkBulbProp" }
function taskTickCallback(p)
    D("taskTickCallback(%1) pluginDevice=%2", p, pluginDevice)
    local stepStamp = tonumber(p,10)
    assert(stepStamp ~= nil)
    if stepStamp ~= runStamp then
        D( "taskTickCallback() stamp mismatch (got %1, expecting %2), newer thread running. Bye!",
            stepStamp, runStamp )
        return
    end

    if not isEnabled( pluginDevice ) then
        gatewayStatus( "DISABLED" )
        return
    end

    local now = os.time()
    local nextTick = nil
    tickTasks._plugin.when = 0

    -- Since the tasks can manipulate the tickTasks table, the iterator
    -- is likely to be disrupted, so make a separate list of tasks that
    -- need service, and service them using that list.
    local todo = {}
    for t,v in pairs(tickTasks) do
        if t ~= "_plugin" and v.when ~= nil and v.when <= now then
            -- Task is due or past due
            D("taskTickCallback() inserting eligible task %1 when %2 now %3", v.id, v.when, now)
            v.when = nil -- clear time; timer function will need to reschedule
            table.insert( todo, v )
        end
    end

    -- Run the to-do list.
    D("taskTickCallback() to-do list is %1", todo)
    for _,v in ipairs(todo) do
        D("taskTickCallback() calling task function %3(%4,%5) for %1 (%2)", v.owner, (luup.devices[v.owner] or {}).description, functions[tostring(v.func)] or tostring(v.func),
            v.owner,v.id)
        local success, err = pcall( v.func, v.owner, v.id, v.args )
        if not success then
            L({level=1,msg="Yeelight device %1 (%2) tick failed: %3"}, v.owner, (luup.devices[v.owner] or {}).description, err)
        else
            D("taskTickCallback() successful return from %2(%1)", v.owner, functions[tostring(v.func)] or tostring(v.func))
        end
    end

    -- Things change while we work. Take another pass to find next task.
    for t,v in pairs(tickTasks) do
        if t ~= "_plugin" and v.when ~= nil then
            if nextTick == nil or v.when < nextTick then
                nextTick = v.when
            end
        end
    end

    -- Figure out next master tick, or don't resched if no tasks waiting.
    if nextTick ~= nil then
        D("taskTickCallback() next eligible task scheduled for %1", os.date("%x %X", nextTick))
        now = os.time() -- Get the actual time now; above tasks can take a while.
        local delay = nextTick - now
        if delay < 1 then delay = 1 end
        tickTasks._plugin.when = now + delay
        D("taskTickCallback() scheduling next tick(%3) for %1 (%2)", delay, tickTasks._plugin.when,p)
        luup.call_delay( "yeelightTaskTick", delay, p )
    else
        D("taskTickCallback() not rescheduling, nextTick=%1, stepStamp=%2, runStamp=%3", nextTick, stepStamp, runStamp)
        tickTasks._plugin.when = nil
    end
end

-- Watch callback. Dispatches to child-specific handling.
function watchCallback( dev, sid, var, oldVal, newVal )
    D("watchCallback(%1,%2,%3,%4,%5)", dev, sid, var, oldVal, newVal)
    assert(var ~= nil) -- nil if service or device watch (can happen on openLuup)
    if sid == MYSID and var == "LocalColorProfiles" then
        local s = luup.variable_get( MYSID, "LocalColorProfiles", pdev ) or ""
        localColors = json.decode( s ) or {}
    end
end

local EOL = "\r\n"

local function getDevice( dev, pdev, v )
    if v == nil then v = luup.devices[dev] end
    if json == nil then json = require("dkjson") end
    local devinfo = {
          devNum=dev
        , ['type']=v.device_type
        , description=v.description or ""
        , room=v.room_num or 0
        , udn=v.udn or ""
        , id=v.id
        , parent=v.device_num_parent or pdev
        , ['device_json'] = luup.attr_get( "device_json", dev )
        , ['impl_file'] = luup.attr_get( "impl_file", dev )
        , ['device_file'] = luup.attr_get( "device_file", dev )
        , manufacturer = luup.attr_get( "manufacturer", dev ) or ""
        , model = luup.attr_get( "model", dev ) or ""
    }
    local rc,t,httpStatus,uri
    if isOpenLuup then
        uri = "http://localhost:3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
    else
        uri = "http://localhost/port_3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
    end
    rc,t,httpStatus = luup.inet.wget(uri, 15)
    if httpStatus ~= 200 or rc ~= 0 then
        devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%s, http=%s', tostring(rc), tostring(httpStatus) )
        return devinfo
    end
    local d = json.decode(t)
    local key = "Device_Num_" .. dev
    if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
    devinfo.states = d or {}
    return devinfo
end

local function alt_json_encode( st )
    str = "{"
    local comma = false
    for k,v in pairs(st) do
        str = str .. ( comma and "," or "" )
        comma = true
        str = str .. '"' .. k .. '":'
        if type(v) == "table" then
            str = str .. alt_json_encode( v )
        elseif type(v) == "number" then
            str = str .. tostring(v)
        elseif type(v) == "boolean" then
            str = str .. ( v and "true" or "false" )
        else
            str = str .. string.format("%q", tostring(v))
        end
    end
    str = str .. "}"
    return str
end

function handleLuupRequest( lul_request, lul_parameters, lul_outputformat )
    D("request(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
    local action = lul_parameters['action'] or lul_parameters['command'] or ""
    local deviceNum = tonumber( lul_parameters['device'], 10 )
    if action == "debug" then
        debugMode = not debugMode
        D("debug set %1 by request", debugMode)
        return "Debug is now " .. ( debugMode and "on" or "off" ), "text/plain"

    elseif action == "status" then
        local st = {
            name=_PLUGIN_NAME,
            plugin=_PLUGIN_ID,
            version=_PLUGIN_VERSION,
            configversion=_CONFIGVERSION,
            author="Patrick H. Rigney (rigpapa)",
            url=_PLUGIN_URL,
            ['type']=MYTYPE,
            responder=luup.device,
            timestamp=os.time(),
            system = {
                version=luup.version,
                isOpenLuup=isOpenLuup,
                isALTUI=isALTUI
            },
            devices={}
        }
        for k,v in pairs( luup.devices ) do
            if v.device_type == MYTYPE or v.device_num_parent == pluginDevice then
                local devinfo = getDevice( k, pluginDevice, v ) or {}
                if k == pluginDevice then
                    devinfo.tickTasks = tickTasks
                    devinfo.devData = devData
                end
                table.insert( st.devices, devinfo )
            end
        end
        return alt_json_encode( st ), "application/json"
        
    elseif action == "listprofiles" then
    
        -- ??? hard-codey for now, use available data structures!
        local data = {}
        data.manufacturers = { { id='@', name='Local Profiles' }, { id='r', name='Roscolux' }, { id='g', name='GamColor' }, { id='l', name='Lee Filters' } }
        data.profiles = {}
        data.profiles.r = Roscolux
        data.profiles.g = GamColor
        data.profiles.l = Lee
        local lc = {}
        for ix,v in pairs( localColors ) do
            table.insert( lc, { id=ix, name=ix, rgb=v } )
        end
        data.profiles['@'] = lc
        data.format = 1
        return json.encode( data ), "application/json"

    else
        error("Not implemented: " .. action)
    end
end

-- Return the plugin version string
function getPluginVersion()
    return _PLUGIN_VERSION, _CONFIGVERSION
end
