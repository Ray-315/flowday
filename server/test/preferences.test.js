import test from 'node:test';
import assert from 'node:assert/strict';
import {emptyData,validateData} from '../src/validation.js';

test('Flutter today module arrays and system timezone are valid workspace preferences',()=>{
  const data={...emptyData(),preferences:{todayModuleOrder:['todo','timeline','calendar'],todayHiddenModules:['workflow','pressure'],timezone:'system'}};
  assert.equal(validateData(data),data);
  assert.equal(validateData({...emptyData(),preferences:{timezone:'Asia/Shanghai',todayModules:['todo']}}).preferences.timezone,'Asia/Shanghai');
});
test('new preference compatibility retains array limits, IANA validation and secret rejection',()=>{
  for(const preferences of [
    {todayModuleOrder:'todo'},
    {todayHiddenModules:[1]},
    {todayModuleOrder:Array(31).fill('todo')},
    {timezone:'unsupported-zone'},
    {timezone:null},
    {arbitraryArray:['todo']},
    {apiKey:'synthetic-test-value'},
  ]) assert.throws(()=>validateData({...emptyData(),preferences}),{code:'VALIDATION_ERROR'});
});
test('legacy Flutter notices with null type remain valid while invalid types are rejected',()=>{
  const notice={id:'legacy',title:'提醒',body:'测试',createdAt:'2026-10-03T00:00:00Z',read:false,acknowledged:false,type:null};
  assert.equal(validateData({...emptyData(),notices:[notice]}).notices[0].type,null);
  assert.throws(()=>validateData({...emptyData(),notices:[{...notice,type:'unsupported'}]}),{code:'VALIDATION_ERROR'});
});
