// budget-wrapper v1: every agent starts through run(); a refused agent stops further starts and reruns on a resume with args.retry
const BUDGET_REFUSED = 'BUDGET-REFUSED'
const budgetMarker = args && args.retry ? ` (budget retry ${args.retry})` : ''
let budgetStopped = false
const budgetIsRefused = r => r === BUDGET_REFUSED || (r !== null && typeof r === 'object' && r.budget_refused === true)
const budgetOpts = o => o && o.schema ? { ...o, schema: { ...o.schema, properties: { ...o.schema.properties, budget_refused: { type: 'boolean' } } } } : o
async function run(prompt, opts) {
  const o = budgetOpts(opts || {})
  if (budgetStopped) return o.schema ? { budget_refused: true } : BUDGET_REFUSED
  let r = await agent(prompt, o)
  if (budgetIsRefused(r) && budgetMarker) r = await agent(prompt + budgetMarker, o)
  if (budgetIsRefused(r)) { budgetStopped = true; log(`refused: ${o.label || 'agent'}; no further agents start`) }
  return r
}
