# NetSuite today: what the sandbox shows

Read from the NetSuite sandbox (`3559546_SB1`) on 20 November 2026 with a
view-only role. Structure only; no prices or customer data are recorded here.
Test item: `OTK20-0040` (internal ID 187131), a 25 lb lapping compound with no
equipment make ("Universal").

## Record types

| Record | ID | Rows | Role today |
|---|---|---|---|
| Inventory item | `inventoryitem` | | The part. Also carries several hundred custom fields of old per-channel data |
| Ecom Record | `customrecord_ecom` | about 1.5 million | One sellable version of an item for one account |
| eCommerce Accounts | `customrecord_ecommerce_accounts` | 7 | Brand and account settings |
| Amazon / eBay / Walmart / Newegg / Sears / PriceFalls Listing | `customrecord_amazonlisting` etc. | not checked | Older per-channel records, not yet examined |

## eCommerce Accounts (7)

Reliable Aftermarket Parts, Stevens Lake, Tractor Parts Accessories, AIC,
Reliable (Canada), Aftermarket Concrete, Aftermarket Powersports.

Each account row holds brand-level settings: brand name, standard bullet
points, filler images, image bucket, pricing margins and fees, the Rithum
profile ID, and switches for which channels the account sells on.

This is the design's "brand layer" in early form.

## Ecom Record

Links: `custrecord_parent` -> item, `custrecord_acct` -> account.

One row covers every channel at once. Channels are groups of columns, not rows:

| Prefix | Channel | Examples |
|---|---|---|
| `custrecord_a_` | Amazon | sell flag, ASIN (`a_id`), floor / ceiling / price, search terms |
| `custrecord_e_` | eBay | sell flag, item ID (`e_id`), prices, shipping, categories |
| `custrecord_w_` | Walmart | sell flag, item ID (`w_id`), prices |
| `custrecord_website_` | Shopify site | sell flag, URL |
| `custrecord_n_` | Newegg | sell flag, ID |

Shared content on the row: seller SKU (`custrecord_sku`), long and short title,
five bullet points, HTML and plain description, 12 image URLs, `custrecord_mpn`
(reference numbers, free text), `custrecord_models` (free text),
`custrecord_equipment`, part type, UPC, package quantity, shipping template,
Rithum product ID, flags for FBA, Walmart fulfilment and do-not-list, and
numbered "item specifics" pairs (brand 1-5, model 1-10, reference number 1-5,
equipment 1-5, technical 1-5, custom 1-10).

## Mapping to the PIM design

| Today | PIM design |
|---|---|
| Inventory item | Item |
| eCommerce Account | Brand / seller account |
| Ecom Record row | Branded product + up to four offers + their listings |
| Channel column group on an Ecom Record | One offer and one listing |
| Title, bullets, models, reference numbers on an Ecom Record | Facts on the item, rendered per listing |
| Account bullet points and filler images | Brand-level content |

## Findings that affect the design

1. **Seven accounts, not four brands.** The model must not hard-code four.
2. **One item already has several sellable versions per account.** The test
   item has three active Reliable records with different seller SKUs, each
   styled after a different vendor part number, each with its own title and its
   own eBay listing. The "branded product" layer therefore needs a general
   variant label (a make, or a reference number), not only a make.
3. **Fitment is free text.** Models and reference numbers are comma-separated
   strings, repeated per Ecom Record. No structured fitment exists to migrate.
4. **Sources already conflict.** The item's own fields and its Ecom Records
   disagree on ASIN, price and the list of reference numbers. The item-level
   channel fields look stale.
5. **No UPCs on the test item.** The UPC field holds "Does Not Apply".
6. **Channel IDs and the Rithum product ID are stored on each Ecom Record.**
   This is most of the SKU map needed for the cutover and for adopting
   existing listings.
7. **FBA, Walmart fulfilment and shipping template are already fields** on the
   Ecom Record.
8. **Images are on Amazon S3,** one bucket per account, not Cloudflare.
9. **Some content is truncated.** A bullet point on the test item is cut off
   mid-sentence at 100 characters.

## Prototype example item: 897788M91

Internal ID 19954. A hood latch assembly for Massey Ferguson and Massey Harris.
Chosen because its data is messy in representative ways.

- 11 reference numbers on the item, 8 vendors. One vendor's part-number field
  holds a warning that its part is different and must not be used.
- 55 Ecom Records: 46 active, 9 inactive, across five accounts (Reliable 24,
  Stevens Lake 19, Tractor Parts Accessories 6, AIC 4, Reliable Canada 2).
- Seller SKUs follow at least six naming patterns: the base number, numbered
  copies (`_1` to `_13`), vendor-number styles, channel suffixes (`-RAP`,
  `-WM`, `-CA`), `-DUP` copies, and unrelated codes.
- 7 different ASINs on the Reliable US account for this one part, plus 2 on
  Canada. The two newest are split by make (Massey Ferguson, Massey Harris).
- 8 different model lists and 11 different reference-number lists across the
  records, with no indication of which is correct.
- Equipment type varies by record: tractor, backhoe, industrial tractor,
  industrial construction.
- About half the active records have no title on the Ecom Record.
- One Reliable-account record has a title that begins "Stevens Lake Parts".

## Not yet examined

- Field labels for the unnamed item fields (`custitem1` to `custitem222`)
- The older per-channel listing record types
- How Ecom Records are created (script, import or by hand)
