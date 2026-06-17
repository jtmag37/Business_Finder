from datetime import datetime
import json
from app import db


class Listing(db.Model):
    __tablename__ = 'listings'

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(500), nullable=False)
    price = db.Column(db.Float, nullable=True)
    price_text = db.Column(db.String(100))
    location = db.Column(db.String(500))
    city = db.Column(db.String(100))
    state = db.Column(db.String(50))
    zip_code = db.Column(db.String(20))
    description = db.Column(db.Text)
    lot_count = db.Column(db.Integer, nullable=True)
    acreage = db.Column(db.Float, nullable=True)
    source = db.Column(db.String(100))
    url = db.Column(db.String(2000))
    source_id = db.Column(db.String(200))
    property_type = db.Column(db.String(100))
    cap_rate = db.Column(db.Float, nullable=True)
    gross_revenue = db.Column(db.Float, nullable=True)
    net_income = db.Column(db.Float, nullable=True)
    year_established = db.Column(db.Integer, nullable=True)
    broker_name = db.Column(db.String(200))
    broker_phone = db.Column(db.String(50))
    broker_email = db.Column(db.String(200))
    images_json = db.Column(db.Text, default='[]')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    is_favorite = db.Column(db.Boolean, default=False)
    notes = db.Column(db.Text, default='')
    status = db.Column(db.String(50), default='active')

    @property
    def images(self):
        try:
            return json.loads(self.images_json or '[]')
        except Exception:
            return []

    @images.setter
    def images(self, value):
        self.images_json = json.dumps(value or [])

    def to_dict(self):
        return {
            'id': self.id,
            'title': self.title,
            'price': self.price,
            'price_text': self.price_text,
            'location': self.location,
            'city': self.city,
            'state': self.state,
            'description': self.description,
            'lot_count': self.lot_count,
            'acreage': self.acreage,
            'source': self.source,
            'url': self.url,
            'property_type': self.property_type,
            'cap_rate': self.cap_rate,
            'gross_revenue': self.gross_revenue,
            'net_income': self.net_income,
            'broker_name': self.broker_name,
            'broker_phone': self.broker_phone,
            'broker_email': self.broker_email,
            'is_favorite': self.is_favorite,
            'notes': self.notes,
            'status': self.status,
            'images': self.images,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }


class ScraperRun(db.Model):
    __tablename__ = 'scraper_runs'

    id = db.Column(db.Integer, primary_key=True)
    source = db.Column(db.String(100))
    started_at = db.Column(db.DateTime, default=datetime.utcnow)
    finished_at = db.Column(db.DateTime, nullable=True)
    listings_found = db.Column(db.Integer, default=0)
    listings_new = db.Column(db.Integer, default=0)
    status = db.Column(db.String(50), default='running')
    error_message = db.Column(db.Text, nullable=True)

    @property
    def duration(self):
        if self.finished_at and self.started_at:
            secs = (self.finished_at - self.started_at).total_seconds()
            return f"{secs:.1f}s"
        return "—"


class AppSettings(db.Model):
    __tablename__ = 'app_settings'

    id = db.Column(db.Integer, primary_key=True)
    key = db.Column(db.String(100), unique=True, nullable=False)
    value = db.Column(db.Text)

    @classmethod
    def get(cls, key, default=None):
        s = cls.query.filter_by(key=key).first()
        return s.value if s else default

    @classmethod
    def set_value(cls, key, value):
        s = cls.query.filter_by(key=key).first()
        if s:
            s.value = str(value)
        else:
            db.session.add(cls(key=key, value=str(value)))
        db.session.commit()
