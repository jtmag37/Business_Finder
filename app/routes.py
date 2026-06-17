import csv
import io
import json
import logging
from datetime import datetime
from functools import wraps

from flask import (
    Blueprint, render_template, request, redirect, url_for,
    jsonify, flash, Response, current_app, session as flask_session
)

from app import db
from app.models import Listing, ScraperRun, AppSettings

main = Blueprint('main', __name__)
logger = logging.getLogger(__name__)

# ── optional HTTP basic auth ────────────────────────────────────────────────

def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        username = current_app.config.get('APP_USERNAME', '')
        password = current_app.config.get('APP_PASSWORD', '')
        if not username or not password:
            return f(*args, **kwargs)
        if flask_session.get('authenticated'):
            return f(*args, **kwargs)
        return redirect(url_for('main.login', next=request.url))
    return decorated


@main.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        u = current_app.config.get('APP_USERNAME', '')
        p = current_app.config.get('APP_PASSWORD', '')
        if request.form.get('username') == u and request.form.get('password') == p:
            flask_session['authenticated'] = True
            return redirect(request.args.get('next') or url_for('main.index'))
        flash('Invalid credentials', 'danger')
    return render_template('login.html')


@main.route('/logout')
def logout():
    flask_session.pop('authenticated', None)
    return redirect(url_for('main.login'))


# ── dashboard ───────────────────────────────────────────────────────────────

@main.route('/')
@login_required
def index():
    total = Listing.query.filter_by(status='active').count()
    favorites = Listing.query.filter_by(is_favorite=True).count()
    by_source = db.session.query(Listing.source, db.func.count()).group_by(Listing.source).all()
    by_type = db.session.query(Listing.property_type, db.func.count()).group_by(Listing.property_type).all()
    recent = Listing.query.filter_by(status='active').order_by(Listing.created_at.desc()).limit(6).all()
    last_runs = ScraperRun.query.order_by(ScraperRun.started_at.desc()).limit(14).all()
    return render_template('index.html',
                           total=total, favorites=favorites,
                           by_source=by_source, by_type=by_type,
                           recent=recent, last_runs=last_runs)


# ── listings ────────────────────────────────────────────────────────────────

@main.route('/listings')
@login_required
def listings():
    q = Listing.query.filter_by(status='active')

    search = request.args.get('q', '').strip()
    if search:
        like = f'%{search}%'
        q = q.filter(
            db.or_(Listing.title.ilike(like), Listing.location.ilike(like),
                   Listing.description.ilike(like))
        )

    state = request.args.get('state', '')
    if state:
        q = q.filter_by(state=state)

    prop_type = request.args.get('type', '')
    if prop_type:
        q = q.filter_by(property_type=prop_type)

    source = request.args.get('source', '')
    if source:
        q = q.filter_by(source=source)

    favs_only = request.args.get('favorites') == '1'
    if favs_only:
        q = q.filter_by(is_favorite=True)

    min_price = request.args.get('min_price', type=float)
    max_price = request.args.get('max_price', type=float)
    if min_price is not None:
        q = q.filter(Listing.price >= min_price)
    if max_price is not None:
        q = q.filter(Listing.price <= max_price)

    min_lots = request.args.get('min_lots', type=int)
    if min_lots is not None:
        q = q.filter(Listing.lot_count >= min_lots)

    sort = request.args.get('sort', 'newest')
    if sort == 'price_asc':
        q = q.order_by(Listing.price.asc().nullslast())
    elif sort == 'price_desc':
        q = q.order_by(Listing.price.desc().nullslast())
    elif sort == 'lots_desc':
        q = q.order_by(Listing.lot_count.desc().nullslast())
    else:
        q = q.order_by(Listing.created_at.desc())

    page = request.args.get('page', 1, type=int)
    pagination = q.paginate(page=page, per_page=24, error_out=False)

    states = [r[0] for r in db.session.query(Listing.state).distinct().filter(Listing.state.isnot(None)).order_by(Listing.state).all()]
    sources = [r[0] for r in db.session.query(Listing.source).distinct().order_by(Listing.source).all()]

    return render_template('listings.html',
                           pagination=pagination,
                           listings=pagination.items,
                           states=states,
                           sources=sources,
                           args=request.args)


@main.route('/listing/<int:listing_id>')
@login_required
def listing_detail(listing_id):
    listing = Listing.query.get_or_404(listing_id)
    return render_template('listing_detail.html', listing=listing)


@main.route('/listing/<int:listing_id>/favorite', methods=['POST'])
@login_required
def toggle_favorite(listing_id):
    listing = Listing.query.get_or_404(listing_id)
    listing.is_favorite = not listing.is_favorite
    db.session.commit()
    return jsonify({'is_favorite': listing.is_favorite})


@main.route('/listing/<int:listing_id>/notes', methods=['POST'])
@login_required
def save_notes(listing_id):
    listing = Listing.query.get_or_404(listing_id)
    listing.notes = request.json.get('notes', '')
    db.session.commit()
    return jsonify({'ok': True})


@main.route('/listing/<int:listing_id>/status', methods=['POST'])
@login_required
def update_status(listing_id):
    listing = Listing.query.get_or_404(listing_id)
    listing.status = request.json.get('status', listing.status)
    db.session.commit()
    return jsonify({'status': listing.status})


# ── export ──────────────────────────────────────────────────────────────────

@main.route('/export/csv')
@login_required
def export_csv():
    listings = Listing.query.filter_by(status='active').order_by(Listing.created_at.desc()).all()
    si = io.StringIO()
    writer = csv.writer(si)
    writer.writerow([
        'Title', 'Price', 'Location', 'State', 'Property Type',
        'Lots', 'Acreage', 'Cap Rate %', 'Gross Revenue', 'Net Income',
        'Source', 'URL', 'Broker', 'Phone', 'Added',
    ])
    for l in listings:
        writer.writerow([
            l.title, l.price_text or l.price, l.location, l.state,
            l.property_type, l.lot_count, l.acreage,
            f"{l.cap_rate:.1f}" if l.cap_rate else '',
            l.gross_revenue, l.net_income,
            l.source, l.url, l.broker_name, l.broker_phone,
            l.created_at.strftime('%Y-%m-%d') if l.created_at else '',
        ])
    output = si.getvalue()
    return Response(
        output,
        mimetype='text/csv',
        headers={'Content-Disposition': 'attachment; filename=rv_park_listings.csv'},
    )


# ── scraper controls ─────────────────────────────────────────────────────────

@main.route('/scrape/run', methods=['POST'])
@login_required
def trigger_scrape():
    from app.scheduler import run_all_scrapers
    import threading
    t = threading.Thread(target=run_all_scrapers, args=[current_app._get_current_object()], daemon=True)
    t.start()
    flash('Scrape started in background — refresh in a few minutes.', 'info')
    return redirect(request.referrer or url_for('main.scraper_status'))


@main.route('/scrape/run/<source>', methods=['POST'])
@login_required
def trigger_single_scrape(source):
    from app.scheduler import run_scraper
    import threading
    cfg = {
        'REQUEST_DELAY': current_app.config.get('REQUEST_DELAY', 2.5),
        'MAX_LISTINGS_PER_SOURCE': current_app.config.get('MAX_LISTINGS_PER_SOURCE', 50),
        'APIFY_API_KEY': current_app.config.get('APIFY_API_KEY', ''),
    }
    app = current_app._get_current_object()
    def _run():
        with app.app_context():
            run_scraper(source, cfg)
    t = threading.Thread(target=_run, daemon=True)
    t.start()
    flash(f'Scrape started for {source}.', 'info')
    return redirect(url_for('main.scraper_status'))


@main.route('/scraper-status')
@login_required
def scraper_status():
    from app.scrapers import ALL_SCRAPERS
    runs = ScraperRun.query.order_by(ScraperRun.started_at.desc()).limit(50).all()
    last_by_source = {}
    for run in runs:
        if run.source not in last_by_source:
            last_by_source[run.source] = run
    return render_template('scraper_status.html',
                           scrapers=ALL_SCRAPERS,
                           last_by_source=last_by_source,
                           recent_runs=runs[:20])


# ── settings ────────────────────────────────────────────────────────────────

@main.route('/settings', methods=['GET', 'POST'])
@login_required
def settings():
    if request.method == 'POST':
        for key in ['notification_email', 'min_price_alert', 'max_price_alert',
                    'min_lots_alert', 'alert_states']:
            AppSettings.set_value(key, request.form.get(key, ''))
        flash('Settings saved.', 'success')
        return redirect(url_for('main.settings'))

    return render_template('settings.html',
                           config=current_app.config,
                           notification_email=AppSettings.get('notification_email', ''),
                           min_price_alert=AppSettings.get('min_price_alert', ''),
                           max_price_alert=AppSettings.get('max_price_alert', ''),
                           min_lots_alert=AppSettings.get('min_lots_alert', ''),
                           alert_states=AppSettings.get('alert_states', ''))


# ── JSON API ─────────────────────────────────────────────────────────────────

@main.route('/api/listings')
def api_listings():
    q = Listing.query.filter_by(status='active')
    state = request.args.get('state')
    if state:
        q = q.filter_by(state=state)
    prop_type = request.args.get('type')
    if prop_type:
        q = q.filter_by(property_type=prop_type)
    page = request.args.get('page', 1, type=int)
    per_page = min(request.args.get('per_page', 50, type=int), 200)
    pagination = q.order_by(Listing.created_at.desc()).paginate(page=page, per_page=per_page, error_out=False)
    return jsonify({
        'total': pagination.total,
        'page': page,
        'per_page': per_page,
        'pages': pagination.pages,
        'listings': [l.to_dict() for l in pagination.items],
    })


@main.route('/api/listings/<int:listing_id>')
def api_listing(listing_id):
    listing = Listing.query.get_or_404(listing_id)
    return jsonify(listing.to_dict())


@main.route('/api/stats')
def api_stats():
    total = Listing.query.filter_by(status='active').count()
    by_source = dict(db.session.query(Listing.source, db.func.count()).group_by(Listing.source).all())
    by_type = dict(db.session.query(Listing.property_type, db.func.count()).group_by(Listing.property_type).all())
    last_run = ScraperRun.query.order_by(ScraperRun.started_at.desc()).first()
    return jsonify({
        'total_listings': total,
        'by_source': by_source,
        'by_type': by_type,
        'last_scraped': last_run.started_at.isoformat() if last_run else None,
    })
