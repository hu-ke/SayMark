"""地理编码与距离计算。

使用 OpenStreetMap Nominatim 做正/逆地理编码（免费，无需 API key）。
计算两点间的直线距离（Haversine 公式）。
"""

import math
import urllib.parse
from dataclasses import dataclass

import httpx

_NOMINATIM_URL = "https://nominatim.openstreetmap.org"
_USER_AGENT = "SayMark/1.0"


@dataclass
class GeoResult:
    """地理编码结果。"""
    name: str          # 显示名称
    lat: float
    lon: float
    distance_km: float | None = None   # 相对某参考点的直线距离（公里）
    travel_note: str = ""              # 距离描述（如 "约3.2km"）


async def geocode(place: str, ref_lat: float | None = None, ref_lon: float | None = None) -> GeoResult | None:
    """根据地名查询坐标。如果有参考点，同时计算距离。"""
    params = {
        "q": place,
        "format": "json",
        "limit": 1,
        "accept-language": "zh",
    }
    url = f"{_NOMINATIM_URL}/search?{urllib.parse.urlencode(params)}"
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(url, headers={"User-Agent": _USER_AGENT})
            resp.raise_for_status()
            data = resp.json()
    except Exception:
        return None

    if not data:
        return None

    item = data[0]
    lat = float(item["lat"])
    lon = float(item["lon"])
    name = item.get("display_name", place)

    result = GeoResult(name=name, lat=lat, lon=lon)

    if ref_lat is not None and ref_lon is not None:
        result.distance_km = haversine_km(ref_lat, ref_lon, lat, lon)
        result.travel_note = _format_distance(result.distance_km)

    return result


async def reverse_geocode(lat: float, lon: float) -> str | None:
    """逆地理编码：坐标 → 地址描述。"""
    params = {
        "lat": lat,
        "lon": lon,
        "format": "json",
        "accept-language": "zh",
    }
    url = f"{_NOMINATIM_URL}/reverse?{urllib.parse.urlencode(params)}"
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            resp = await client.get(url, headers={"User-Agent": _USER_AGENT})
            resp.raise_for_status()
            data = resp.json()
    except Exception:
        return None

    return data.get("display_name") if data else None


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Haversine 公式计算两点间直线距离（公里）。"""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    )
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _format_distance(km: float) -> str:
    """格式化距离描述。"""
    if km < 1:
        return f"约{int(km * 1000)}米"
    return f"约{km:.1f}km"
