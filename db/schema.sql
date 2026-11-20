-- PIM prototype schema, draft 1 (2026-11-20).
-- Plain-language walk-through: docs/schema.md
-- Status and type columns are text with CHECK constraints so the allowed
-- values are easy to change while the design is still moving.

-- ---------------------------------------------------------------------------
-- Reference data
-- ---------------------------------------------------------------------------

-- A seller account: the "Sold by" entity. Mirrors NetSuite eCommerce Accounts.
CREATE TABLE seller_account (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    netsuite_id   bigint UNIQUE,
    name          text NOT NULL UNIQUE,
    brand_name    text NOT NULL,          -- brand shown on listings this account owns
    is_active     boolean NOT NULL DEFAULT true
);

-- Brand-level wording reused on every listing an account owns
-- (warranty text, phone number, standard bullets).
CREATE TABLE brand_content (
    seller_account_id bigint NOT NULL REFERENCES seller_account(id),
    content_key       text NOT NULL,
    content_value     text NOT NULL,
    PRIMARY KEY (seller_account_id, content_key)
);

CREATE TABLE channel (
    code  text PRIMARY KEY,               -- amazon, ebay, walmart, shopify-rap
    name  text NOT NULL
);

-- The kinds of fact the PIM can hold about an item.
-- Adding a new kind of fact is a new row here, not a new column anywhere.
CREATE TABLE attribute (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code          text NOT NULL UNIQUE,   -- part_type, length_in, fits_model, replaces_part_number
    label         text NOT NULL,
    data_type     text NOT NULL CHECK (data_type IN ('text', 'number', 'boolean')),
    is_multi      boolean NOT NULL DEFAULT false,  -- many values per item (fits_model) or one (length_in)
    uses_make     boolean NOT NULL DEFAULT false,  -- facts of this kind carry an equipment make
    risk          text NOT NULL DEFAULT 'high' CHECK (risk IN ('low', 'high'))  -- high = a person must approve
);

-- ---------------------------------------------------------------------------
-- Items and what we know about them
-- ---------------------------------------------------------------------------

-- The physical part. Mirrors the NetSuite inventory item; NetSuite owns it.
CREATE TABLE item (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    netsuite_id  bigint NOT NULL UNIQUE,
    sku          text NOT NULL UNIQUE,
    description  text,
    synced_at    timestamptz NOT NULL DEFAULT now()
);

-- Data exactly as it arrived from somewhere else, before anything interprets it.
CREATE TABLE raw_import (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_system  text NOT NULL,         -- netsuite, rithum, amazon, vendor:<name>
    record_type    text NOT NULL,         -- ecom_record, item, catalog_item, price_file_row
    external_id    text,
    item_id        bigint REFERENCES item(id),
    payload        jsonb NOT NULL,
    imported_at    timestamptz NOT NULL DEFAULT now()
);

-- Where a fact came from. One row per piece of evidence.
CREATE TABLE source (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind           text NOT NULL CHECK (kind IN
                     ('vendor', 'agent', 'staff', 'legacy', 'channel_page', 'rule')),
    label          text NOT NULL,         -- "Sparex catalogue 2026", "Ecom Record 82697"
    url            text,
    excerpt        text,                  -- the passage that supports the fact
    agent_version  text,                  -- which agent version produced it, if any
    raw_import_id  bigint REFERENCES raw_import(id),
    retrieved_at   timestamptz NOT NULL DEFAULT now()
);

-- One thing we believe about an item. This is the heart of the PIM.
-- Facts are never edited: a correction retires the old row and adds a new one.
CREATE TABLE fact (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id         bigint NOT NULL REFERENCES item(id),
    attribute_id    bigint NOT NULL REFERENCES attribute(id),
    make            text,                 -- equipment make this fact applies to, when the attribute uses one
    value           text NOT NULL,
    is_negative     boolean NOT NULL DEFAULT false,  -- true = "does NOT fit" / "is NOT interchangeable"
    confidence      numeric(3,2) CHECK (confidence BETWEEN 0 AND 1),
    status          text NOT NULL DEFAULT 'proposed' CHECK (status IN
                      ('proposed', 'approved', 'rejected', 'retired')),
    replaces_fact_id bigint REFERENCES fact(id),     -- the fact this one corrects
    proposed_by     text NOT NULL,
    decided_by      text,
    decided_at      timestamptz,
    decision_note   text,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX fact_item_idx ON fact (item_id, attribute_id, status);

-- A fact can rest on several pieces of evidence, and one source can support several facts.
CREATE TABLE fact_source (
    fact_id    bigint NOT NULL REFERENCES fact(id),
    source_id  bigint NOT NULL REFERENCES source(id),
    PRIMARY KEY (fact_id, source_id)
);

CREATE TABLE image (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id             bigint NOT NULL REFERENCES item(id),
    branded_product_id  bigint,           -- set only for brand-specific images; FK added below
    url                 text NOT NULL,
    role                text NOT NULL CHECK (role IN ('main', 'angle', 'dimensions', 'in_use', 'packaging')),
    position            int NOT NULL DEFAULT 1,
    source_id           bigint REFERENCES source(id),
    status              text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'approved', 'rejected', 'retired'))
);

-- ---------------------------------------------------------------------------
-- What we sell and where
-- ---------------------------------------------------------------------------

-- The item as sold by one seller account from one angle (a make, a reference
-- number, or no angle at all). Worked out from the offers; not a NetSuite record.
CREATE TABLE branded_product (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    item_id            bigint NOT NULL REFERENCES item(id),
    seller_account_id  bigint NOT NULL REFERENCES seller_account(id),
    variant            text NOT NULL DEFAULT '',   -- 'Massey Ferguson', '184779M92', or ''
    part_number        text NOT NULL,
    UNIQUE (item_id, seller_account_id, variant)
);
ALTER TABLE image
    ADD CONSTRAINT image_branded_product_fk
    FOREIGN KEY (branded_product_id) REFERENCES branded_product(id);

-- One page on one channel.
CREATE TABLE listing (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    channel_code        text NOT NULL REFERENCES channel(code),
    item_id             bigint NOT NULL REFERENCES item(id),
    branded_product_id  bigint REFERENCES branded_product(id),  -- empty for joined listings
    listing_type        text NOT NULL CHECK (listing_type IN ('owned', 'joined')),
    control             text NOT NULL DEFAULT 'managed' CHECK (control IN ('legacy', 'managed')),
    channel_listing_id  text,             -- ASIN, eBay item ID, Walmart item ID
    brand_on_listing    text,
    product_type        text,             -- the channel's own category for this product
    status              text NOT NULL DEFAULT 'draft' CHECK (status IN
                          ('draft', 'waiting_for_content', 'ready', 'submitted', 'live', 'error', 'blocked')),
    status_message      text,
    UNIQUE (channel_code, channel_listing_id)
);

-- Our sale on a listing. Mirrors the NetSuite offer record; NetSuite owns it.
CREATE TABLE offer (
    id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    netsuite_id        bigint UNIQUE,
    item_id            bigint NOT NULL REFERENCES item(id),
    seller_account_id  bigint NOT NULL REFERENCES seller_account(id),
    channel_code       text NOT NULL REFERENCES channel(code),
    variant            text NOT NULL DEFAULT '',
    seller_sku         text NOT NULL,
    price              numeric(10,2),
    fulfilment         text NOT NULL DEFAULT 'merchant' CHECK (fulfilment IN ('merchant', 'channel')),
    shipping_template  text,
    is_active          boolean NOT NULL DEFAULT false,
    listing_id         bigint REFERENCES listing(id),
    synced_at          timestamptz NOT NULL DEFAULT now(),
    -- An incoming order line must find exactly one offer.
    UNIQUE (seller_account_id, channel_code, seller_sku)
);

-- ---------------------------------------------------------------------------
-- Channel rules and what was sent
-- ---------------------------------------------------------------------------

-- What a channel wants for a kind of product, one field per row.
-- A new requirement from Amazon is a new row, not a schema change.
CREATE TABLE channel_rule (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    channel_code    text NOT NULL REFERENCES channel(code),
    product_type    text NOT NULL DEFAULT '*',   -- '*' = applies to every product type
    field_code      text NOT NULL,               -- the channel's own name for the field
    is_required     boolean NOT NULL DEFAULT false,
    max_length      int,
    max_bytes       int,
    max_items       int,
    allowed_values  jsonb,
    built_from      text,                        -- how the PIM fills it: a template or an attribute code
    is_assumed      boolean NOT NULL DEFAULT true,  -- true until confirmed against the channel's own schema
    UNIQUE (channel_code, product_type, field_code)
);

-- A hand-written value that replaces the generated one for a single listing.
CREATE TABLE listing_override (
    listing_id  bigint NOT NULL REFERENCES listing(id),
    field_code  text NOT NULL,
    value       text NOT NULL,
    reason      text NOT NULL,
    set_by      text NOT NULL,
    set_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (listing_id, field_code)
);

-- A frozen copy of a listing's content at one moment.
CREATE TABLE listing_snapshot (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    listing_id  bigint NOT NULL REFERENCES listing(id),
    kind        text NOT NULL CHECK (kind IN ('sent', 'observed')),  -- sent by us, or read from the channel
    payload     jsonb NOT NULL,
    result      text,                      -- the channel's answer, for 'sent'
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- Which fact versions a sent snapshot was built from.
CREATE TABLE listing_snapshot_fact (
    snapshot_id  bigint NOT NULL REFERENCES listing_snapshot(id),
    fact_id      bigint NOT NULL REFERENCES fact(id),
    PRIMARY KEY (snapshot_id, fact_id)
);

-- ---------------------------------------------------------------------------
-- Problems reported after the sale
-- ---------------------------------------------------------------------------

-- Raised by customer service on the NetSuite offer, reviewed by a person here.
CREATE TABLE issue (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    netsuite_id  bigint UNIQUE,
    offer_id     bigint NOT NULL REFERENCES offer(id),
    reason_code  text NOT NULL,
    note         text,
    order_ref    text,
    status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    outcome      text CHECK (outcome IN ('our_data_wrong', 'page_wrong', 'customer_error')),
    raised_at    timestamptz NOT NULL DEFAULT now(),
    closed_at    timestamptz
);

-- The facts that were live when the problem order was placed.
CREATE TABLE issue_fact (
    issue_id  bigint NOT NULL REFERENCES issue(id),
    fact_id   bigint NOT NULL REFERENCES fact(id),
    PRIMARY KEY (issue_id, fact_id)
);
