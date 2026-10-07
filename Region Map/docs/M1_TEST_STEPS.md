# Region Map V2 - M1 player-side test steps

You run these on the **player client**. I do the Director side through the DMHub bridge
on your Director client. Where a step says **[Claude]**, tell me and wait for me to
confirm before going on.

There is no V2 window yet, so every step is one chat command. Type it in the player
client's chat exactly as shown (one line, starting with `/lua`). Results come back as a
private chat message titled **RM test**. After a step marked **(write)**, wait about
2 seconds: the server has to confirm the write first.

If a result differs from "Expected", stop and send me the step number and the message.

## Setup

- The player client must load the V2 code from this machine's dev-mod folder
  (`C:\Users\ElderHex\codex-dev-mods`), so run it on this PC. A client on another PC loads
  the cloud copy, which does not have the V2 code yet.
- Log the player client into the same game as your Director client (the game with
  Region1).
- **[Claude]** Before P1, I put a Hidden test pin, "Secret test", on Region1 from the
  Director side.

## Steps

**P0. Helper** (defines `say` and the short names used below)
```
/lua M=RegionMapModel U=RegionMapUndo function say(...) local t={} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end SendTitledChatMessage(table.concat(t,' | '),'RM test',nil,{dmhub.loginUserid}) end say('ready','director',dmhub.isDM)
```
Expected: `ready | director | false`. If a later step says `say` is nil, run P0 again.

**P1. What the player sees**
```
/lua local t=M.TopLevel()[1] local n={} for _,c in ipairs(M.Children(t.id)) do n[#n+1]=c.name end say('maps',#M.TopLevel(),'pins',#n,table.concat(n,', '))
```
Expected: `maps | 1 | pins | 2 | Player Location, ` followed by the Director's label.
"Secret test" must not be there.

**P2. Player creates a location (write)** - this is the V2-00 check
```
/lua local ok,r,e,id=M.CreateLocation(M.TopLevel()[1].id,0.45,0.55) RMP={pin=id} say('create',ok,r)
```
Expected: `create | true | nil`

**P3. It arrived, and it is the player's own**
```
/lua local p=M.GetLocation(RMP.pin) say('found',p~=nil,'vis',p and p.visibility,'owner',p and p.ownerName,'can edit',M.CanEdit(p))
```
Expected: `found | true | vis | revealed | owner | <player name> | can edit | true`.
If `found | false` even after 10 seconds, players cannot write tables: tell me (the
shared-document fallback, decision 8.2, then applies).

**[Claude]** I check from the Director side that the row arrived with the player as owner.

**P4. Rename it (write)**
```
/lua local ok,r=M.UpdateLocation(RMP.pin,{name='Player test'}) say('rename',ok,r)
```
Expected: `rename | true | nil`

**P5. Things a player may not do**
```
/lua local t=M.TopLevel()[1] local a={M.UpdateLocation(t.id,{name='x'})} local b={M.SetVisibility(RMP.pin,'hidden')} local c={M.CreateMap('x',t.imageId)} say('edit map',a[1],a[2],'hide own',b[1],b[2],'new map',c[1],c[2])
```
Expected: `edit map | false | permission | hide own | false | permission | new map | false | permission`

**P6. Another person's location**
```
/lua local o for _,c in ipairs(M.Children(M.TopLevel()[1].id)) do if c.ownerId~=dmhub.loginUserid then o=c end end local ok,r=M.MoveLocation(o.id,0.1,0.1) say('move other',o.name,ok,r)
```
Expected: `move other | <label name> | false | permission`

**P7. Delete own, then undo (writes)**
```
/lua local ok,r,e,n=M.DeleteLocation(RMP.pin) RMP.de=e say('delete',ok,r,'gone',M.GetLocation(RMP.pin)==nil)
```
Expected: `delete | true | nil | gone | true`. Wait 2 seconds, then:
```
/lua U.Undo(RMP.de,function(ok) say('undo',ok) end)
```
Expected: `undo | true`. Wait 2 seconds, then:
```
/lua say('back',M.GetLocation(RMP.pin)~=nil)
```
Expected: `back | true`

**P8. Party permission**
```
/lua local ok,r,e=M.WriteParty{mapId=M.TopLevel()[1].id,locationId=RMP.pin} RMP.pe=e say('party',ok,r)
```
Expected: `party | false | permission` ("Players can move Party" is currently off in this
game). Optional: **[Claude]** I turn it on, you run P8 again and expect `party | true | nil`,
then put the Party back (write):
```
/lua U.Undo(RMP.pe,function(ok) say('party undo',ok) end)
```
Expected: `party undo | true`; the Party is back where it was.

**P9. Visibility changes reach the player**

**[Claude]** I reveal "Secret test". Then run P1 again.
Expected: `pins | 4`, now including "Secret test" and "Player test".

**P10. The Director's "players can add" switch**

**[Claude]** I turn "Players can add locations" off. Then:
```
/lua say('can add',M.CanAdd(M.TopLevel()[1].id))
```
Expected: `can add | false | permission`. **[Claude]** I turn it back on.

**P11. Clean up (write)**
```
/lua local ok,r=M.DeleteLocation(RMP.pin) say('deleted',ok,r)
```
Expected: `deleted | true | nil`

**[Claude]** I delete "Secret test" and remove the test rows from the Director side.
