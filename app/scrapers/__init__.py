from app.scrapers.bizbuysell import BizBuySellScraper
from app.scrapers.rvparkstore import RVParkStoreScraper
from app.scrapers.mobilehomeparkstore import MobileHomeParkStoreScraper
from app.scrapers.loopnet import LoopNetScraper
from app.scrapers.mhvillage import MHVillageScraper
from app.scrapers.crexi import CrexiScraper
from app.scrapers.landwatch import LandWatchScraper

ALL_SCRAPERS = [
    BizBuySellScraper,
    RVParkStoreScraper,
    MobileHomeParkStoreScraper,
    MHVillageScraper,
    LoopNetScraper,
    CrexiScraper,
    LandWatchScraper,
]

SCRAPER_MAP = {s.name: s for s in ALL_SCRAPERS}
