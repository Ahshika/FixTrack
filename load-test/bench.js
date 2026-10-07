// قياس أقصى سرعة: 30 جهاز بيبعتوا عمليات ورا بعض من غير توقف لمدة 40 ثانية
import { setup as fullSetup, operation } from './fixtrack_full.js';
export const options = { scenarios: { max: { executor: 'constant-vus', vus: 30, duration: '40s', exec: 'run' } }, setupTimeout: '120s' };
export function setup() { return fullSetup(); }
export function run(d) { operation(d); }
