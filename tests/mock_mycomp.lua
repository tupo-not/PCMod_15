function table.Copy(t) if type(t)~='table' then return t end local o={} for k,v in pairs(t) do o[k]=table.Copy(v) end return o end
local function assertTrue(v,m) if not v then error('FAILED: '..m,2) end end
local function assertEq(a,b,m) if a~=b then error('FAILED: '..m..' got '..tostring(a)..' want '..tostring(b),2) end end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
string.Replace=function(s,pat,rep) return (string.gsub(s,pat,rep)) end
surface={SetFont=function() end,GetTextSize=function(t) return #tostring(t)*6,10 end,SetDrawColor=function() end,DrawRect=function() end,DrawOutline=function() end,DrawLine=function() end}
draw={SimpleText=function() end}
TEXT_ALIGN_LEFT=0; TEXT_ALIGN_CENTER=1
math.Clamp=function(v,a,b) if v<a then return a end if v>b then return b end return v end
CurTime=function() return 0 end
local el
PCMod={Msg=function() end,SDraw={CFrame=0,GetGuiScale=function() return 1.25 end},Cfg={GuiScale=1.25},Gui={Themes={basic={NiceName='Basic'},dark={NiceName='Dark'}},GetThemeColour=function() return Color(0,0,0,255) end,ThemeDraw=function() return false end,CalcTextWrap=function() return {} end},SSEL={Create=function()
  el={Valid=true,SetTheme=function(self) end,SetLayout=function(self,x,y,w,h) self.X=x self.Y=y self.W=w self.H=h end,SetText=function(self,t) self.Text=t end,SetIcon=function(self) end,SetFunc=function(self,n,f) self[n]=f end,IsValid=function(self) return self.Valid end,Remove=function(self) self.Valid=false end,CursorInside=function() return false end,Paint=function() end}
  return el
end}}
DEV={}
dofile("sh_ui_layout.lua")
dofile("sh_window.lua")
dofile("cl_ui_widgets.lua")
keyboard={GetLatency=function() return 150 end,GetHoldTime=function() return 400 end,SetLatency=function(v) keyboard.Latency=v end,SetHoldTime=function(v) keyboard.Hold=v end}
dofile('ss_base.lua')
dofile('mycomp.lua')
local d=table.Copy(DEV)
d.Th='basic'
d:OnCreate()
d:Initialize(10,20,800,600)
assertTrue(d.Listboxes.lstGuiScale ~= nil, 'scale list exists')
assertEq(#d.Listboxes.lstGuiScale.Order, 7, 'seven scale presets')
assertEq(d:GetListboxSelRow('lstGuiScale'), '1.25', 'current scale selected')
local ran
local ranlist={}
RunConsoleCommand=function(cmd,val) ran={cmd=cmd,val=val}; table.insert(ranlist,{cmd=cmd,val=val}) end
d:ButtonClick('btnApplyScale')
assertTrue(ran and ran.cmd=='pc_guiscale' and ran.val=='1.25', 'apply scale command')
assertEq(#d.Listboxes.lstSections.Order, 4, 'four control panel categories')
d.Net={MAC='AA:BB:CC:DD:EE:FF',IPv4='192.168.1.2',Static='192.168.5.7',Mask='255.255.255.0',Gateway4='192.168.5.1',IPv6='fd00:c0:a8:1::2',Prefix='fd00:c0:a8:1::/64',Gateway='fd00:c0:a8:1::1',LinkLocal='fe80::2'}
d.Wireless={{EntIndex=12,Class='pcmod_router',Distance=342,Signal=80}}
d:ListboxSelect('lstSections','network')
assertTrue(d.Listboxes.lstNetInfo ~= nil, 'network page exists')
assertTrue(d.Listboxes.lstWireless == nil, 'wireless controls live on their own page')
assertTrue(d.Listboxes.lstGuiScale == nil, 'OS controls hidden on network page')
assertEq(#d.Listboxes.lstNetInfo.Order, 9, 'network information rows')
assertTrue(string.find(d.Listboxes.lstNetInfo.List.mac, 'AA:BB:CC:DD:EE:FF', 1, true) ~= nil, 'MAC address shown')
assertTrue(string.find(d.Listboxes.lstNetInfo.List.gateway, 'fd00:c0:a8:1::1', 1, true) ~= nil, 'IPv6 gateway shown')
assertTrue(string.find(d.Listboxes.lstNetInfo.List.gateway4, '192.168.5.1', 1, true) ~= nil, 'IPv4 gateway shown')
assertTrue(string.find(d.Listboxes.lstNetInfo.List.netmask, '255.255.255.0', 1, true) ~= nil, 'netmask shown')
assertTrue(string.find(d.Listboxes.lstNetInfo.List.static, '192.168.5.7', 1, true) ~= nil, 'static IP shown')
assertTrue(d.Textboxes.txtStaticIP ~= nil, 'static IP box exists')
assertTrue(d.Textboxes.txtNetmask ~= nil, 'netmask box exists')
assertTrue(d.Textboxes.txtGateway ~= nil, 'gateway box exists')
assertTrue(d.Textboxes.txtMac ~= nil, 'MAC box exists')
assertEq(d:GetTextboxText('txtStaticIP'), '192.168.5.7', 'static IP prefilled')
assertEq(d:GetTextboxText('txtNetmask'), '255.255.255.0', 'netmask prefilled')
assertEq(d:GetTextboxText('txtGateway'), '192.168.5.1', 'gateway prefilled')
assertEq(d:GetTextboxText('txtMac'), 'AA:BB:CC:DD:EE:FF', 'MAC prefilled')
assertTrue(d.Textboxes.txtWifiPass == nil, 'wifi password box moved off network page')
d:ListboxSelect('lstSections','wifi')
assertTrue(d.Listboxes.lstWireless ~= nil, 'wireless networks list exists')
assertTrue(d.Listboxes.lstNetInfo == nil, 'network status hidden on wifi page')
assertEq(#d.Listboxes.lstWireless.Order, 1, 'wireless network listed')
assertTrue(string.find(d.Listboxes.lstWireless.List['12'], 'Signal 80%', 1, true) ~= nil, 'wireless signal shown')
assertTrue(d.Textboxes.txtWifiPass ~= nil, 'wifi password box exists')
d:SetListboxSelRow('lstWireless','12')
d:SetTextboxText('txtWifiPass','123')
local wsent
function d:RunProgCommand(prog,cmd,a,b,c,e) wsent={prog=prog,cmd=cmd,a=a,b=b,c=c,e=e} end
d:ButtonClick('btnWifiConnect')
assertTrue(wsent and wsent.cmd=='connect_wifi' and wsent.a=='12' and wsent.b=='123', 'wifi connect command')
d:ButtonClick('btnRefreshWifi')
assertTrue(wsent and wsent.cmd=='refresh_wifi', 'wifi scan command')
d:ListboxSelect('lstSections','network')
d:ButtonClick('btnRenewNetwork')
assertTrue(wsent and wsent.cmd=='renew_network', 'renew DHCP command')
d:SetTextboxText('txtStaticIP','192.168.5.20')
d:SetTextboxText('txtNetmask','255.255.255.0')
d:SetTextboxText('txtGateway','192.168.5.1')
d:SetTextboxText('txtMac','11:22:33:44:55:66')
d:ButtonClick('btnApplyNetwork')
assertTrue(wsent and wsent.cmd=='set_network' and wsent.a=='192.168.5.20' and wsent.b=='255.255.255.0' and wsent.c=='192.168.5.1' and wsent.e=='11:22:33:44:55:66', 'apply network command')
d.Net.Static = nil
d.Net.IPv4 = '192.168.1.2'
d:SetTextboxText('txtStaticIP','192.168.1.2')
d:ButtonClick('btnApplyNetwork')
assertTrue(wsent and wsent.cmd=='set_network' and wsent.a=='', 'unchanged DHCP address stays DHCP')
d.Dvs={{1,'Printer'},{4,'Keyboard'}}
local sent
function d:RunProgCommand(prog,cmd) sent={prog=prog,cmd=cmd} end
d:ListboxSelect('lstSections','io')
assertTrue(d.Listboxes.lstDevices ~= nil, 'IO page exists')
assertEq(#d.Listboxes.lstDevices.Order, 2, 'identified devices listed')
assertTrue(d.Textboxes.txtKeyRepeat ~= nil, 'key repeat box exists')
assertTrue(d.Textboxes.txtKeyHold ~= nil, 'key hold box exists')
assertEq(d:GetTextboxText('txtKeyRepeat'), '150', 'current repeat shown')
assertEq(d:GetTextboxText('txtKeyHold'), '400', 'current hold shown')
ranlist={}
d:SetTextboxText('txtKeyRepeat','abc')
d:ButtonClick('btnApplyKeyRepeat')
assertEq(#ranlist, 0, 'invalid repeat not applied')
assertTrue(d.KeyRepeatError ~= nil, 'invalid repeat error shown')
ranlist={}
d:SetTextboxText('txtKeyRepeat','100')
d:SetTextboxText('txtKeyHold','250')
d:ButtonClick('btnApplyKeyRepeat')
assertEq(#ranlist, 2, 'repeat and hold applied')
assertTrue(ranlist[1].cmd=='pc_keyrepeat' and ranlist[1].val=='100', 'repeat command')
assertTrue(ranlist[2].cmd=='pc_keyhold' and ranlist[2].val=='250', 'hold command')
assertEq(keyboard.Latency, 100, 'keyboard repeat applied')
assertEq(keyboard.Hold, 250, 'keyboard hold applied')
assertTrue(d.KeyRepeatError == nil, 'error cleared')
d:ButtonClick('btnRefreshDevices')
assertTrue(sent and sent.prog=='mycomputer' and sent.cmd=='refresh_devices', 'device refresh command')
d:ListboxSelect('lstSections','os')
assertTrue(d.Listboxes.lstThemes ~= nil, 'OS page restored')
assertEq(d:GetListboxSelRow('lstSections'), 'os', 'OS category selected')
print('MYCOMP TESTS PASSED')
