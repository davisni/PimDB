# Decision log

Decisions reached in discussion. Add new ones at the bottom with a date.

| Date | Decision | Reason |
|---|---|---|
| 2026-11-18 | Build a separate PIM in Postgres rather than extend NetSuite records | Millions of rows, provenance and history are awkward in NetSuite |
| 2026-11-18 | NetSuite keeps items, stock, cost, offers and price | Customer service and finance work there |
| 2026-11-18 | All business logic (mappings, validation, defaults) lives in the PIM; the transport only delivers | Keeps Versori replaceable; no hidden rules as in Rithum |
| 2026-11-18 | Agents propose facts and never write live data | Fitment errors drive returns |
| 2026-11-18 | Fitment and specs need human approval; low-risk copy can be approved by rule | Risk differs by field |
| 2026-11-18 | Customer service flags problems with an issue record on the offer in NetSuite, reviewed by a person in the PIM | A return is not always a data error |
| 2026-11-19 | Vocabulary: item, branded product, listing (owned or joined), offer, fact | "Offer" was being used for two things |
| 2026-11-19 | No silent defaults. A default is a visible PIM rule or the listing fails its check | Rithum hides defaults today |
| 2026-11-19 | Existing listings are adopted as legacy and flipped to managed gradually; no one-time bulk load | Current data is too disjointed |
| 2026-11-19 | PIM is built in parallel with the Versori cutover and does not block it | Rithum ends 2026-12-21 |
| 2026-11-19 | Code, server setup and agent definitions go in Azure DevOps; secrets in 1Password | Existing company tools |
| 2026-11-19 | Images stay on Cloudflare; the PIM records address, role, order, source and approval | Smallest change to the current pipeline |
| 2026-11-20 | Build a small local prototype (a handful of sandbox items) to make the design tangible | See data move before committing to the schema |
