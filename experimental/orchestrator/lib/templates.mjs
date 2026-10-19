const stage = (id, title, instruction, x, y = 160, options = {}) => ({
  id, title, kind: 'task', instruction, position: { x, y }, ...options
});
const edge = (source, target) => ({ id: `${source}-${target}`, source, target });

export const TEMPLATES = Object.freeze({
  blank: { id: 'blank', name: 'Blank workflow', nodes: [], edges: [] },
  software_factory: {
    id: 'software_factory', name: 'Software factory',
    nodes: [
      stage('intake', 'Intake', 'Inspect the assigned repository read-only. Turn the work item into a bounded implementation brief with acceptance criteria, relevant files, a test command and risks. Do not expand the scope.', 80),
      stage('build', 'Build', 'Implement the accepted brief in this isolated workspace. Add focused tests, run them, and report changed files and actual results. Preserve unrelated work. Do not publish or install dependencies without separate approval.', 400, 160, { policy: 'workspace-write', maxAttempts: 2 }),
      stage('review', 'Review', 'Independently inspect the isolated implementation and tests. Lead with concrete defects, then verification evidence and residual risks. Explicitly state whether the acceptance criteria are met. Do not edit files or claim a test ran unless you ran it. Return for human review.', 720, 160, { routing: 'approval' }),
      stage('release', 'Release gate', 'Prepare a release handoff from the accepted evidence: changed artifacts, verification receipts, remaining risks, rollback steps and the exact next deployment action. Do not publish, merge, install or change external accounts. A human must approve the handoff.', 1040, 160, { routing: 'approval' })
    ], edges: [edge('intake', 'build'), edge('build', 'review'), edge('review', 'release')]
  },
  research: {
    id: 'research', name: 'Research desk',
    nodes: [
      stage('brief', 'Question brief', 'Convert the input into a precise research question, scope, exclusions and evidence standard. Identify assumptions rather than inventing answers.', 80),
      stage('primary', 'Primary evidence', 'Research the brief with primary sources. Cite direct source URLs, dates and relevant findings. Separate observations from inference and flag inaccessible evidence.', 400, 40, { webSearch: true, slots: 2 }),
      stage('challenge', 'Counter-evidence', 'Independently challenge the brief: seek counterexamples, contradictory evidence and alternative explanations. Cite sources. Do not treat an absence of evidence as proof.', 400, 300, { webSearch: true, slots: 2 }),
      stage('synthesis', 'Synthesis', 'Combine both accepted evidence streams into one decision brief. Resolve disagreements where possible, preserve uncertainty, cite sources and give a bounded recommendation. Do not fabricate missing evidence.', 720, 160, { join: 'all' }),
      stage('review', 'Editorial review', 'Audit the synthesis for unsupported claims, source quality, scope and clear conclusions. Return a final brief and unresolved issues for human acceptance.', 1040, 160, { routing: 'approval' })
    ], edges: [edge('brief', 'primary'), edge('brief', 'challenge'), edge('primary', 'synthesis'), edge('challenge', 'synthesis'), edge('synthesis', 'review')]
  },
  marketing: {
    id: 'marketing', name: 'Marketing and SEO',
    nodes: [
      stage('brief', 'Campaign intake', 'Extract audience, product facts, objective, channel constraints and supplied brand voice. Flag missing claims or approvals. Do not invent prices, endorsements or performance promises.', 80),
      stage('search', 'Search intent', 'Research current search intent and competing coverage using public sources. Cite the evidence. Produce a focused keyword and content opportunity brief without invented search volumes.', 400, 40, { webSearch: true }),
      stage('message', 'Message strategy', 'Develop factual positioning and campaign angles from the brief. Preserve supplied brand voice, limitations and product claims. Identify what must not be promised.', 400, 300),
      stage('draft', 'Content studio', 'Combine the accepted search and messaging outputs. Create channel-ready drafts, metadata and a publishing checklist. Keep factual sources and open questions visible. Do not publish or access social accounts.', 720, 160, { join: 'all' }),
      stage('approval', 'Brand and claims gate', 'Review the content for factual accuracy, brand fit, accessibility, unsupported claims and channel constraints. Return approved-ready copy and remaining issues. Publication remains a separate human action.', 1040, 160, { routing: 'approval' })
    ], edges: [edge('brief', 'search'), edge('brief', 'message'), edge('search', 'draft'), edge('message', 'draft'), edge('draft', 'approval')]
  },
  engineering: {
    id: 'engineering', name: 'Engineering investigation',
    nodes: [
      stage('triage', 'Triage', 'Reproduce or bound the reported issue with available local evidence. Record expected versus observed behavior, affected scope and unknowns. Do not modify files.', 80),
      stage('diagnose', 'Root-cause analysis', 'Evaluate the accepted reproduction evidence. Trace likely causes, test alternatives and propose the smallest justified repair. Distinguish a supported cause from a hypothesis.', 400),
      stage('repair', 'Repair', 'Implement the bounded repair and a regression test in the isolated workspace. Run relevant checks and report exact results. Do not publish, change accounts or hide unrelated failures.', 720, 160, { policy: 'workspace-write', maxAttempts: 2 }),
      stage('review', 'Independent review', 'Inspect the repair and regression evidence. Identify regressions, missing tests and operational risks. Return a clear acceptance recommendation for human review.', 1040, 160, { routing: 'approval' })
    ], edges: [edge('triage', 'diagnose'), edge('diagnose', 'repair'), edge('repair', 'review')]
  },
  outcome_learning: {
    id: 'outcome_learning', name: 'Outcome learning (opt-in)',
    nodes: [
      stage('evidence', 'Outcome evidence', 'Use only the explicitly supplied accepted prior-queue inputs, native verification metadata and artifact paths. Build a concise retrospective of intended outcome, observed outcome, deviations, failed or passed checks and known limits. Treat missing fields as unknown; do not infer tool timings, token metrics, costs or model behavior, and do not read raw secrets or harvest logs.', 80),
      stage('hypothesis', 'Improvement hypothesis', 'From the accepted retrospective, propose one concrete workflow or prompt change and state the hypothesis it is meant to test. Separate observed evidence from interpretation. Do not change policy, permissions, routing, provider settings or workflow definitions in this stage; this is analysis only.', 400),
      stage('evaluation', 'Bounded evaluation', 'Design a small, reversible evaluation against the preserved baseline: name the comparison, success and failure criteria, sample or run bound, artifacts to inspect and stop condition. Do not claim that evaluation data exists until a human runs and accepts it. Do not perform fake model training or automatically apply the recommendation.', 720),
      stage('approval', 'Human acceptance gate', 'Return the retrospective, evidence references, proposed change, hypothesis and bounded evaluation as a recommendation package. A human must explicitly accept any follow-up; acceptance does not itself alter workflow, policy, permissions, providers or accounts. Preserve the baseline and leave rejected or unproven recommendations unapplied.', 1040, 160, { routing: 'approval' })
    ], edges: [edge('evidence', 'hypothesis'), edge('hypothesis', 'evaluation'), edge('evaluation', 'approval')]
  },
  tool_call_review: {
    id: 'tool_call_review', name: 'Tool-call efficiency review (opt-in)',
    nodes: [
      stage('evidence', 'Tool-call evidence', 'Review only explicitly supplied accepted prior-queue inputs, native verification metadata and artifact paths. Identify redundant, failed, repeated or avoidable tool-call patterns from those artifacts. Use observed evidence only: never invent timings, token counts, cost, provider behavior or success rates, and never inspect raw secrets or harvest logs.', 80),
      stage('workflow', 'Workflow improvement', 'Propose one concrete, reversible tool-call or workflow improvement with a clear hypothesis and the evidence supporting it. Keep capability and routing unchanged unless a human later accepts a separate change. Do not modify permissions, policy, provider configuration or the active workflow automatically.', 400),
      stage('evaluation', 'Bounded comparison', 'Define a bounded comparison with the current baseline, including the exact artifact inputs, success and failure criteria, run limit, stop condition and what evidence a human must collect. Do not claim timing or token savings without observed measurements; do not perform fake model training or apply changes automatically.', 720),
      stage('approval', 'Human acceptance gate', 'Return the observed call pattern, proposed improvement, hypothesis and bounded evaluation as a recommendation package. Route it for explicit human acceptance. Keep the existing workflow and baseline intact; no approval here may silently change policy, permissions, routing, provider settings or accounts.', 1040, 160, { routing: 'approval' })
    ], edges: [edge('evidence', 'workflow'), edge('workflow', 'evaluation'), edge('evaluation', 'approval')]
  }
});
