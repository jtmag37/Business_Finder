import logging
from datetime import datetime

from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger

logger = logging.getLogger(__name__)
_scheduler = None


def run_scraper(scraper_name, app_config):
    """Run a single scraper and persist results. Called by APScheduler."""
    from app import db
    from app.models import Listing, ScraperRun
    from app.scrapers import SCRAPER_MAP

    scraper_cls = SCRAPER_MAP.get(scraper_name)
    if not scraper_cls:
        logger.error(f"Unknown scraper: {scraper_name}")
        return

    scraper = scraper_cls(config=app_config)
    run = ScraperRun(source=scraper_name, started_at=datetime.utcnow())
    db.session.add(run)
    db.session.commit()

    try:
        listings = scraper.scrape()
        new_count = 0

        for data in listings:
            # dedup by source + source_id or url
            existing = None
            if data.get('source_id'):
                existing = Listing.query.filter_by(
                    source=scraper_name, source_id=data['source_id']
                ).first()
            if not existing and data.get('url'):
                existing = Listing.query.filter_by(url=data['url']).first()

            if existing:
                # update price / status
                existing.price = data.get('price') or existing.price
                existing.price_text = data.get('price_text') or existing.price_text
                existing.updated_at = datetime.utcnow()
            else:
                listing = Listing(
                    title=data.get('title', 'Untitled'),
                    price=data.get('price'),
                    price_text=data.get('price_text'),
                    location=data.get('location'),
                    city=data.get('city'),
                    state=data.get('state'),
                    zip_code=data.get('zip_code'),
                    description=data.get('description'),
                    lot_count=data.get('lot_count'),
                    acreage=data.get('acreage'),
                    source=scraper_name,
                    url=data.get('url'),
                    source_id=data.get('source_id'),
                    property_type=data.get('property_type'),
                    cap_rate=data.get('cap_rate'),
                    gross_revenue=data.get('gross_revenue'),
                    net_income=data.get('net_income'),
                    broker_name=data.get('broker_name'),
                    broker_phone=data.get('broker_phone'),
                    broker_email=data.get('broker_email'),
                )
                listing.images = data.get('images', [])
                db.session.add(listing)
                new_count += 1

        run.listings_found = len(listings)
        run.listings_new = new_count
        run.status = 'success'
        run.finished_at = datetime.utcnow()
        db.session.commit()
        logger.info(f"[{scraper_name}] done — {len(listings)} found, {new_count} new")

    except Exception as exc:
        run.status = 'failed'
        run.error_message = str(exc)
        run.finished_at = datetime.utcnow()
        db.session.commit()
        logger.error(f"[{scraper_name}] failed: {exc}")


def run_all_scrapers(app):
    """Run every enabled scraper. Intended for scheduler or manual trigger."""
    from app.scrapers import ALL_SCRAPERS
    cfg = {
        'REQUEST_DELAY': app.config.get('REQUEST_DELAY', 2.5),
        'MAX_LISTINGS_PER_SOURCE': app.config.get('MAX_LISTINGS_PER_SOURCE', 50),
        'APIFY_API_KEY': app.config.get('APIFY_API_KEY', ''),
    }
    with app.app_context():
        for cls in ALL_SCRAPERS:
            run_scraper(cls.name, cfg)


def init_scheduler(app):
    global _scheduler
    if _scheduler and _scheduler.running:
        return

    interval_hours = app.config.get('SCRAPE_INTERVAL_HOURS', 6)
    _scheduler = BackgroundScheduler(daemon=True)
    _scheduler.add_job(
        func=run_all_scrapers,
        args=[app],
        trigger=IntervalTrigger(hours=interval_hours),
        id='scrape_all',
        replace_existing=True,
    )
    _scheduler.start()
    logger.info(f"Scheduler started — scraping every {interval_hours}h")
