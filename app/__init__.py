from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from config import Config

db = SQLAlchemy()

def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    db.init_app(app)

    with app.app_context():
        from app import models
        db.create_all()

        from app.routes import main
        app.register_blueprint(main)

        from app.scheduler import init_scheduler
        init_scheduler(app)

    return app
