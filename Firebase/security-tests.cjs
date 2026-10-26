const fs = require('node:fs');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {ref, get, set, remove} = require('firebase/database');
(async () => {
  const rulesText = fs.readFileSync('database.rules.json','utf8');
  // The rules name the owner and sensor UIDs literally (placeholders in the repository, real UIDs once
  // deployed). The emulator accepts any UID string, so the tests sign in as whatever the rules say.
  const rules = JSON.parse(rulesText).rules;
  const uidIn = (rule) => rule.match(/auth\.uid === '([^']+)'/)[1];
  const OWNER_UID = uidIn(rules.viewers['.read']);
  const SENSOR_UID = uidIn(rules.latest['home-in']['.write']);
  const env = await initializeTestEnvironment({projectId:'demo-schoolair-family',database:{host:'127.0.0.1',port:9000,rules:rulesText}});
  const owner = env.authenticatedContext(OWNER_UID).database();
  const sensor = env.authenticatedContext(SENSOR_UID).database();
  const familyID = 'abcdefghijklmnopqrstuvwxyz12';
  const family = env.authenticatedContext(familyID).database();
  const stranger = env.authenticatedContext('unapproved-phone').database();
  const anon = env.unauthenticatedContext().database();
  let count=0;
  async function allow(label, action) {await assertSucceeds(action); count++; console.log('PASS '+label);}
  async function deny(label, action) {await assertFails(action); count++; console.log('PASS '+label);}
  try {
    await env.clearDatabase();
    const paths=['latest/home-in','latest/portable','readings/home-in','readings/portable'];
    for(const path of paths) {
      await allow('owner reads '+path,get(ref(owner,path)));
      await deny('unapproved family cannot read '+path,get(ref(family,path)));
      await deny('unsigned caller cannot read '+path,get(ref(anon,path)));
    }
    await deny('family cannot approve himself',set(ref(family,'viewers/'+familyID),'Family'));
    await deny('stranger cannot approve family',set(ref(stranger,'viewers/'+familyID),'Family'));
    await deny('sensor cannot grant access',set(ref(sensor,'viewers/'+familyID),'Family'));
    await allow('owner approves family',set(ref(owner,'viewers/'+familyID),'Family phone'));
    await allow('family reads own approval',get(ref(family,'viewers/'+familyID)));
    await allow('owner lists approved phones',get(ref(owner,'viewers')));
    await deny('family cannot list other phones',get(ref(family,'viewers')));
    await deny('family cannot read another approval',get(ref(family,'viewers/other')));
    for(const path of paths) {
      await allow('approved family reads '+path,get(ref(family,path)));
      await deny('stranger still cannot read '+path,get(ref(stranger,path)));
      await deny('family cannot write '+path,set(ref(family,path),{t:1,pm25:1}));
    }
    await deny('family cannot overwrite an individual reading',set(ref(family,'readings/portable/test'),{t:1}));
    await deny('family cannot approve another phone',set(ref(family,'viewers/other'),'Other'));
    await deny('owner cannot overwrite sensor data',set(ref(owner,'latest/home-in'),{co2:1}));
    for(const node of ['home-in','portable']) {
      await allow('sensor continues latest uploads '+node,set(ref(sensor,'latest/'+node),{t:1,value:500}));
      await allow('sensor continues history appends '+node,set(ref(sensor,'readings/'+node+'/first'),{t:1,value:500}));
      await deny('sensor cannot overwrite history '+node,set(ref(sensor,'readings/'+node+'/first'),{t:2}));
      await deny('sensor cannot delete history '+node,remove(ref(sensor,'readings/'+node+'/first')));
    }
    for(const bad of [true,'', 'x'.repeat(41), {name:'Family'}]) {
      await deny('invalid viewer record rejected '+JSON.stringify(bad),set(ref(owner,'viewers/invalid'),bad));
    }
    await allow('empty object is a deletion, not an approval',set(ref(owner,'viewers/empty'),{}));
    await deny('owner ID cannot become viewer record',set(ref(owner,'viewers/'+OWNER_UID),'Owner'));
    await deny('sensor ID cannot become viewer record',set(ref(owner,'viewers/'+SENSOR_UID),'Sensor'));
    await deny('database root remains private',get(ref(family)));
    await allow('owner revokes family',remove(ref(owner,'viewers/'+familyID)));
    for(const path of paths) await deny('revoked family cannot read '+path,get(ref(family,path)));
    await allow('revoked family can see own status',get(ref(family,'viewers/'+familyID)));
    console.log(`SECURITY TESTS PASSED: ${count}`);
  } finally {await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1;});
