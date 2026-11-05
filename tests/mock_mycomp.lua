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
RunConsoleCommand=function(cmd,val) ran={cmd=cmd,val=val} end
d:ButtonClick('btnApplyScale')
assertTrue(ran and ran.cmd=='pc_guiscale' and ran.val=='1.25', 'apply scale command')
assertEq(#d.Listboxes.lstSections.Order, 3, 'three control panel categories')
d.Net={IPv4='192.168.1.2',Static='192.168.5.7',IPv6='fd00:c0:a8:1::2',Prefix='fd00:c0:a8:1::/64',Gateway='fd00:c0:a8:1::1',LinkLocal='fe80::2'}
d.Wireless={{EntIndex=12,Class='pcmod_router',Distance=342,Signal=80}}
d:ListboxSelect('lstSections','network')
assertTrue(d.Listboxes.lstNetInfo ~= nil, 'network page exists')
assertTrue(d.Listboxes.lstWireless ~= nil, 'wireless networks list exists')
assertTrue(d.Listboxes.lstGuiScale == nil, 'OS controls hidden on network page')
assertEq(#d.Listboxes.lstNetInfo.Order, 6, 'network information rows')
assertTrue(string.find(d.Listboxes.lstNetInfo.List.gateway, 'fd00:c0:a8:1::1', 1, true) ~= nil, 'gateway shown')
assertTrue(string.find(d.Listboxes.lstNetInfo.List.static, '192.168.5.7', 1, true) ~= nil, 'static IP shown')
assertEq(#d.Listboxes.lstWireless.Order, 1, 'wireless network listed')
assertTrue(string.find(d.Listboxes.lstWireless.List['12'], 'Signal 80%', 1, true) ~= nil, 'wireless signal shown')
assertTrue(d.Textboxes.txtWifiPass ~= nil, 'wifi password box exists')
d:SetListboxSelRow('lstWireless','12')
d:SetTextboxText('txtWifiPass','123')
local wsent
function d:RunProgCommand(prog,cmd,a,b) wsent={prog=prog,cmd=cmd,a=a,b=b} end
d:ButtonClick('btnWifiConnect')
assertTrue(wsent and wsent.cmd=='connect_wifi' and wsent.a=='12' and wsent.b=='123', 'wifi connect command')
d.Dvs={{1,'Printer'},{4,'Keyboard'}}
local sent
function d:RunProgCommand(prog,cmd) sent={prog=prog,cmd=cmd} end
d:ListboxSelect('lstSections','io')
assertTrue(d.Listboxes.lstDevices ~= nil, 'IO page exists')
assertEq(#d.Listboxes.lstDevices.Order, 2, 'identified devices listed')
d:ButtonClick('btnRefreshDevices')
assertTrue(sent and sent.prog=='mycomputer' and sent.cmd=='refresh_devices', 'device refresh command')
d:ListboxSelect('lstSections','os')
assertTrue(d.Listboxes.lstThemes ~= nil, 'OS page restored')
assertEq(d:GetListboxSelRow('lstSections'), 'os', 'OS category selected')
print('MYCOMP TESTS PASSED')
