"""PIM prototype screens. Throwaway UI over the real draft schema."""
import os
from collections import OrderedDict

import psycopg
from fastapi import FastAPI, Form, Request
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from psycopg.rows import dict_row

DATABASE_URL = os.environ["DATABASE_URL"]
REVIEWER = "demo user"

app = FastAPI(title="PIM prototype")
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")


def connect():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


def render(request, name, **context):
    return templates.TemplateResponse(request, name, context)


# ---------------------------------------------------------------------------
# Reading facts
# ---------------------------------------------------------------------------

def load_facts(conn, item_id, status=None):
    """Facts for an item, each with the list of sources that support it."""
    facts = conn.execute(
        """
        SELECT f.id, f.make, f.value, f.is_negative, f.confidence, f.status,
               f.proposed_by, f.decided_by, f.decision_note,
               a.code AS attribute_code, a.label AS attribute_label, a.risk
        FROM fact f
        JOIN attribute a ON a.id = f.attribute_id
        WHERE f.item_id = %s AND (%s::text IS NULL OR f.status = %s)
        ORDER BY a.id, f.make NULLS FIRST, f.value
        """,
        (item_id, status, status),
    ).fetchall()
    sources = conn.execute(
        """
        SELECT fs.fact_id, s.kind, s.label, s.excerpt
        FROM fact_source fs
        JOIN source s ON s.id = fs.source_id
        JOIN fact f ON f.id = fs.fact_id
        WHERE f.item_id = %s
        ORDER BY s.id
        """,
        (item_id,),
    ).fetchall()
    by_fact = {}
    for s in sources:
        by_fact.setdefault(s["fact_id"], []).append(s)
    for f in facts:
        f["sources"] = by_fact.get(f["id"], [])
    return facts


def group_facts(facts):
    """attribute label -> make -> [facts], keeping query order."""
    groups = OrderedDict()
    for f in facts:
        makes = groups.setdefault(f["attribute_label"], OrderedDict())
        makes.setdefault(f["make"] or "", []).append(f)
    return groups


# ---------------------------------------------------------------------------
# Building a listing from approved facts
# ---------------------------------------------------------------------------

def build_listing(conn, listing_id):
    listing = conn.execute(
        """
        SELECT l.*, c.name AS channel_name, i.sku AS item_sku, i.description AS item_description,
               o.seller_sku, o.price, o.variant, o.fulfilment, o.shipping_template, o.is_active,
               sa.id AS seller_account_id, sa.name AS seller_account, bp.part_number
        FROM listing l
        JOIN channel c ON c.code = l.channel_code
        JOIN item i ON i.id = l.item_id
        LEFT JOIN offer o ON o.listing_id = l.id
        LEFT JOIN seller_account sa ON sa.id = o.seller_account_id
        LEFT JOIN branded_product bp ON bp.id = l.branded_product_id
        WHERE l.id = %s
        """,
        (listing_id,),
    ).fetchone()
    if listing is None:
        return None
    result = {"listing": listing, "fields": [], "used": [], "waiting": 0, "blockers": [], "notes": []}
    if listing["listing_type"] == "joined" or listing["control"] == "legacy":
        return result

    variant = listing["variant"] or ""
    facts = load_facts(conn, listing["item_id"])
    approved = [f for f in facts if f["status"] == "approved" and not f["is_negative"]]

    def relevant(f):
        if f["attribute_code"] != "fits_model":
            return True
        return f["make"] == variant if variant else f["make"] != "Not stated"

    result["waiting"] = sum(1 for f in facts if f["status"] == "proposed" and relevant(f))

    part_type = next((f for f in approved if f["attribute_code"] == "part_type"), None)
    part_name = part_type["value"] if part_type else listing["item_description"]
    refs = [f for f in approved if f["attribute_code"] == "replaces_part_number"]
    fitment = OrderedDict()
    for f in approved:
        if f["attribute_code"] == "fits_model" and relevant(f):
            fitment.setdefault(f["make"], []).append(f)
    result["used"] = ([part_type] if part_type else []) + [f for fs in fitment.values() for f in fs] + refs

    if variant and variant not in fitment:
        result["blockers"].append(f"No approved fitment for {variant}.")
    if not fitment and not variant:
        result["blockers"].append("No approved fitment for any make.")

    fits_text = "; ".join(f"{make} {', '.join(f['value'] for f in fs)}" for make, fs in fitment.items())
    if not fits_text and variant:
        fits_text = variant
    brand_bullets = [r["content_value"] for r in conn.execute(
        "SELECT content_value FROM brand_content WHERE seller_account_id = %s ORDER BY content_key",
        (listing["seller_account_id"],))]

    rules = conn.execute(
        "SELECT * FROM channel_rule WHERE channel_code = %s ORDER BY id", (listing["channel_code"],)
    ).fetchall()
    for rule in rules:
        values = []
        if rule["built_from"] == "template:title":
            title = f"{part_name} fits {fits_text}" if fits_text else part_name
            limit = rule["max_length"]
            added = []
            for ref in refs:  # add reference numbers only while the title stays inside the limit
                candidate = f"{title}, replaces {', '.join(added + [ref['value']])}"
                if limit and len(candidate) > limit:
                    break
                added.append(ref["value"])
            if added:
                title = f"{title}, replaces {', '.join(added)}"
            if len(added) < len(refs):
                result["notes"].append(
                    f"Title: {len(refs) - len(added)} of {len(refs)} reference numbers left out to fit the limit.")
            values = [title]
        elif rule["built_from"] == "template:bullets":
            bullets = [f"Aftermarket replacement {part_name.lower()}"]
            bullets += [f"Fits {make}: {', '.join(f['value'] for f in fs)}" for make, fs in fitment.items()]
            if refs:
                bullets.append("Replaces part numbers: " + ", ".join(r["value"] for r in refs))
            bullets += brand_bullets
            if rule["max_items"] and len(bullets) > rule["max_items"]:
                result["notes"].append(
                    f"Bullets: {len(bullets) - rule['max_items']} dropped to fit the limit of {rule['max_items']}.")
                bullets = bullets[: rule["max_items"]]
            values = bullets
        elif rule["built_from"] == "template:description":
            parts = [f"One aftermarket replacement {part_name.lower()}."]
            parts += [f"Fits {make}: {', '.join(f['value'] for f in fs)}." for make, fs in fitment.items()]
            if refs:
                parts.append("Replaces part numbers: " + ", ".join(r["value"] for r in refs) + ".")
            values = [" ".join(parts)]
        elif rule["built_from"] == "listing.brand_on_listing":
            values = [listing["brand_on_listing"]] if listing["brand_on_listing"] else []
        elif rule["built_from"] == "branded_product.part_number":
            values = [listing["part_number"]] if listing["part_number"] else []

        problems = []
        if rule["is_required"] and not values:
            problems.append("Required, but empty.")
        if rule["max_length"]:
            problems += [f"{len(v)} characters; the limit is {rule['max_length']}."
                         for v in values if len(v) > rule["max_length"]]
        if rule["max_items"] and len(values) > rule["max_items"]:
            problems.append(f"{len(values)} items; the limit is {rule['max_items']}.")
        # "vals", not "values": in a template, field.values would be the dict method
        result["fields"].append({"rule": rule, "vals": values, "problems": problems})
        result["blockers"] += [f"{rule['field_code']}: {p}" for p in problems]
    return result


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

@app.get("/")
def home():
    return RedirectResponse("/items/1")


@app.get("/items/{item_id}")
def item_page(request: Request, item_id: int):
    with connect() as conn:
        item = conn.execute("SELECT * FROM item WHERE id = %s", (item_id,)).fetchone()
        facts = load_facts(conn, item_id)
        counts = conn.execute(
            """
            SELECT (SELECT count(*) FROM raw_import WHERE item_id = %(i)s AND record_type = 'ecom_record') AS records,
                   (SELECT count(*) FROM listing WHERE item_id = %(i)s AND control = 'legacy') AS legacy_listings,
                   (SELECT count(*) FROM offer WHERE item_id = %(i)s) AS offers
            """,
            {"i": item_id},
        ).fetchone()
    status_counts = {s: sum(1 for f in facts if f["status"] == s) for s in ("approved", "proposed", "rejected", "retired")}
    return render(request, "item.html", item=item, groups=group_facts(facts), counts=counts,
                  status_counts=status_counts, total=len(facts))


@app.get("/items/{item_id}/before")
def before_page(request: Request, item_id: int):
    with connect() as conn:
        item = conn.execute("SELECT * FROM item WHERE id = %s", (item_id,)).fetchone()
        records = conn.execute(
            """
            SELECT external_id, payload FROM raw_import
            WHERE item_id = %s AND record_type = 'ecom_record'
            ORDER BY payload->>'isinactive', payload->>'account', external_id::bigint
            """,
            (item_id,),
        ).fetchall()
    return render(request, "before.html", item=item, records=records)


@app.get("/review")
def review_page(request: Request):
    with connect() as conn:
        item = conn.execute("SELECT * FROM item WHERE id = 1").fetchone()
        facts = load_facts(conn, 1, status="proposed")
    return render(request, "review.html", item=item, groups=group_facts(facts), total=len(facts))


@app.post("/facts/{fact_id}/decide")
def decide(fact_id: int, action: str = Form(...), note: str = Form("")):
    status = {"approve": "approved", "reject": "rejected", "reopen": "proposed"}[action]
    decided = status != "proposed"
    with connect() as conn:
        conn.execute(
            """
            UPDATE fact
            SET status = %s, decided_by = %s, decided_at = CASE WHEN %s THEN now() END, decision_note = %s
            WHERE id = %s
            """,
            (status, REVIEWER if decided else None, decided, note or None, fact_id),
        )
    return RedirectResponse("/review" if decided else "/items/1", status_code=303)


@app.get("/offers")
def offers_page(request: Request):
    with connect() as conn:
        offers = conn.execute(
            """
            SELECT o.*, i.sku AS item_sku, sa.name AS seller_account, c.name AS channel_name,
                   l.listing_type, l.brand_on_listing, l.channel_listing_id, l.status, l.status_message
            FROM offer o
            JOIN item i ON i.id = o.item_id
            JOIN seller_account sa ON sa.id = o.seller_account_id
            JOIN channel c ON c.code = o.channel_code
            JOIN listing l ON l.id = o.listing_id
            ORDER BY o.id
            """
        ).fetchall()
        legacy = conn.execute(
            """
            SELECT c.name AS channel_name, count(*) AS listings
            FROM listing l JOIN channel c ON c.code = l.channel_code
            WHERE l.control = 'legacy' GROUP BY c.name ORDER BY c.name
            """
        ).fetchall()
    return render(request, "offers.html", offers=offers, legacy=legacy)


@app.get("/listings/{listing_id}")
def listing_page(request: Request, listing_id: int):
    with connect() as conn:
        built = build_listing(conn, listing_id)
    return render(request, "listing.html", **built)
