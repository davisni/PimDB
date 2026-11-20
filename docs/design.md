# RAP PIM design

Draft 2, 20 November 2026. Discussion stage, nothing built yet.
Visual version: https://claude.ai/artifact/JiNYjnqXUtEGYEcoQ6xYTf (source copy in `rap-pim-design.html`).

## Goal

Replace the listing data spread across NetSuite eCom subrecords and Rithum with a
Product Information Management (PIM) database that holds everything a listing
says, the evidence behind it, and the rules each sales channel applies.

Fitment errors are the main driver of returns and bad ratings, so the design
centres on where each piece of information came from and who approved it.

## Who owns what

| System | Owns | Does not own |
|---|---|---|
| NetSuite | Items, stock, cost, offers, price, orders, issue records from customer service | Titles, descriptions, fitment, images |
| PIM (Postgres) | Facts with sources, branded products, listings, channel rules, review queues, publish status | Stock, orders, money |
| Transport (Versori today) | Delivery, retries, logins to each channel | Any business rule |

- The PIM produces the final channel-shaped payload. The transport maps nothing,
  so it can later be replaced by our own scripts.
- Orders and stock flow NetSuite <-> transport <-> channels and never pass
  through the PIM. If the PIM is down, selling continues.

## Vocabulary

| Term | Lives in | Meaning |
|---|---|---|
| Item | NetSuite | The physical part. One per part. |
| Branded product | PIM | The item as sold under one of our brands for one equipment make. Has its own part number and UPC. |
| Listing | PIM | One page on one channel (an ASIN, a Walmart item, an eBay listing, a Shopify product). Owned (we wrote it) or joined (someone else's page). |
| Offer | NetSuite | Our sale on a listing from one seller account: seller SKU, price, shipping template. Replaces the eCom record. |
| Fact | PIM | One piece of information about an item, with source, confidence and approval status. |

Seller accounts today (NetSuite eCommerce Accounts): Reliable Aftermarket
Parts, Stevens Lake, Tractor Parts Accessories, AIC, Reliable (Canada),
Aftermarket Concrete, Aftermarket Powersports.

A branded product's variant is a listing angle: an equipment make, a reference
number, or none.

### Brand, seller and shipper

An Amazon product page shows three names. The design keeps them apart.

| On the page | Meaning | Lives on | Owned listing | Joined listing |
|---|---|---|---|---|
| Brand, under the title | Who makes the product. Shared by every seller on the page | Listing (PIM) | One of our brands | Someone else's, or Generic |
| Sold by | The seller account making this offer | Offer: seller account | RAP, SLP, ... | RAP, SLP, ... |
| Ships from | Who sends the parcel: seller, or Amazon for FBA | Offer: fulfilment | Merchant or Amazon | Merchant or Amazon |

The offer carries all three as separate fields. Seller account and fulfilment
are choices we make. Brand on listing is filled in: from the seller account's
brand name on an owned listing, from the page on a joined one.

## The offer record (NetSuite)

One new custom record, built beside the Ecom Record and deployed with SDF from
`netsuite/`. One offer = one item on one channel from one seller account.

| Group | Field | Notes |
|---|---|---|
| What, where | Item | Link to the inventory item |
| | Seller account | Link to eCommerce Accounts |
| | Channel | Amazon, eBay, Walmart, a Shopify store. Text for now |
| | Variant | A make, a reference number, or blank. Text for now |
| | Seller SKU | What the channel calls it |
| Commercial | Price | Set by the pricing team |
| | Fulfilment | Merchant or FBA |
| | Shipping template | |
| | Active | |
| Listing | Listing type | Owned or Joined |
| | Brand on listing | The brand shown under the title. Filled in, not chosen |
| | Channel ID | Written back for owned; typed in for joined |
| Status (from PIM) | Status, Message, PIM link, Last synced | |

Unique on seller account + channel + seller SKU.

Not on it: listing content, sales figures, price floor and ceiling (parked),
quantity rules (parked), pack quantity (a set is its own item and SKU).

Amazon's listings API has an offer-only mode (`LISTING_OFFER_ONLY`) for adding
an offer to an existing ASIN, which matches the joined listing type.

## Example 1: new listings

One mower blade (item `MB-2054`), replacing a Kubota and a New Holland blade,
sold on Amazon and Walmart under RAP and SLP, one listing per make for ad
targeting.

- 1 item
- 4 branded products: RAP/Kubota, RAP/New Holland, SLP/Kubota, SLP/New Holland
- 8 listings (each branded product on 2 channels), all owned
- 8 offers, all drawing on one pool of stock

Seller SKU = the branded product's part number (for example `RAP-MB2054-KUB`).
The offer record says which item that means.

## Example 2: joined listing

The same blade already has an ASIN created by someone else.

- 1 item, 0 branded products, 1 joined listing, 1 offer per seller account
- The PIM stores a snapshot of the page and never pushes content to it
- Match check: page claims are compared with our approved facts. A mismatch
  (wrong pack quantity, unverified fitment) blocks or flags the offer
- Joined pages are re-snapshotted on a schedule and diffed
- Joining a page under another company's registered brand needs approval

## Facts

- Stored once against the item, never copied onto listings. Listings are
  assembled from current approved facts each time they are built.
- Fitment facts carry a make tag so a per-make listing picks up only its make.
- Never edited in place. A change creates a new version; the old one is kept.
- Sources: vendor file, agent research, staff entry, channel snapshot, legacy
  system, default rule.
- Agents propose and never write live. Low-risk fields can be approved by rule;
  fitment and specs need a human approver.
- Vendor OEM cross-references are unreliable. Agents confirm the part's identity
  first and only then enrich from it.
- An agent's own confidence score is not trusted alone. Corroboration between
  independent sources counts for more, and auto-approved values are sampled.
- Each fact records the agent version that produced it.
- When a fact changes, every listing using it is rebuilt, re-validated and
  re-sent. A snapshot records what was sent and which fact versions were used.

Tables in outline: fact, source, listing, listing snapshot (plus item,
branded product, offer mirror, channel rule, image, issue).

## Images

- Today: OneDrive folder named by NetSuite internal ID -> pipeline converts and
  resizes -> hosted on Cloudflare -> URLs written to NetSuite.
- Keep that. Add: the pipeline's last step also writes to the PIM.
- Each image gets a record: item, role, order, source, approval.
- Attached to the item by default, or to a branded product for brand packaging.
- Listings choose from the approved set; channel image rules are PIM checks.
- Source is recorded because copied images carry ownership and logo risk.

## Life of a new item

1. NetSuite: bare item created, synced to the PIM immediately.
2. NetSuite: offers created in bulk by rule or spreadsheet. Pricing in parallel.
3. PIM: vendor data loaded as received, turned into facts, item scored for how
   researchable it is.
4. PIM agents: confirm identity, then propose facts with sources.
5. PIM people: review. Low-risk approved by rule, fitment by a reviewer.
6. PIM: listings built from approved facts and checked against channel rules.
7. Transport: sends when content is approved, price is set and offer is active.
8. Channel: ID or error written back to the PIM; status and link shown on the
   NetSuite offer.
9. NetSuite: customer service can add an issue record to an offer. It lands in
   the PIM review queue linked to the facts live at the time.

## Shipping templates

A named set of delivery rules inside a seller account. Each offer points to
one. The template name belongs on the offer record. The PIM keeps a list of
valid template names per account and checks offers against it.

## Infrastructure

Proposed: IONOS VPS (Debian 12, Docker, nginx in front, Microsoft 365 sign-in).

| Topic | Good enough to start | Needed before live listings |
|---|---|---|
| Where it runs | Existing server | Its own machine |
| Backups | Nightly copy off the server, one practice restore | Continuous backup |
| People | One admin, setup in Azure DevOps | Two or three trained admins, recovery steps written |
| Testing | Sandbox accounts | Separate test copy of the PIM |
| Monitoring | None | Alerts for disk, memory, failed backups |
| Transport access | Read-only | Narrow write access for IDs, errors, issue flags |

Code and agent definitions in Azure DevOps. Secrets in 1Password.

## Cutover

Rithum ends 21 December 2026, hard cut to Versori, no overlap. Moving orders,
stock and price is a separate project. Four PIM tasks share that date:

1. Export everything from Rithum (templates, defaults, mappings, lookup lists,
   listing IDs, SKU mappings).
2. Build one complete map of every live channel SKU to its NetSuite item.
3. Leave the current eCom record alone; build the new offer record beside it.
4. Decide how new listings and content edits happen until the PIM is ready.

Loading today's listings: pull from every channel plus Rithum and NetSuite as
labelled facts; register each listing as legacy (PIM sends nothing); flip to
managed one at a time as content is verified, in order of revenue and returns.
