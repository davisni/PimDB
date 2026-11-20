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
| 2026-11-20 | Prototype runs in Docker on the work MacBook; code in a private personal GitHub repo until Azure DevOps is set up | Quick start; company data stays out of Git |
| 2026-11-20 | New NetSuite offer record is built beside the Ecom Record, not by changing it | The Versori cutover depends on the Ecom Record |
| 2026-11-20 | NetSuite customisations are defined as code with SDF in `netsuite/` and deployed to the sandbox | The offer record will change often; same files go to production later |
| 2026-11-20 | Imported definitions of existing records are kept in `netsuite/reference/`, outside the deploy path | Reference only; must never be redeployed |
| 2026-11-20 | Offer fields: item and seller account are links; other fields start as free text | Links prevent orphans; reference lists come later |
| 2026-11-20 | The offer carries three separate fields matching the Amazon page: brand on listing, seller account (sold by), fulfilment (ships from) | On a joined listing the page's brand is someone else's; showing all three makes the difference obvious |
| 2026-11-20 | Price floor/ceiling and quantity rules are left off the offer for now | To be discussed later |
| 2026-11-20 | Pack quantity is not an offer field. A set is sold as its own item and SKU | Keeps the offer simple |
| 2026-11-20 | Demo data: a cleaned-up version of item 897788M91, with the real 55 Ecom Records as the "before" | Shows current mess and target state for the same part |
