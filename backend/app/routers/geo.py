"""地理编码 API —— 地名查坐标 + 距离计算。"""

from fastapi import APIRouter, Query

from ..services import geo

router = APIRouter(prefix="/api/geo", tags=["geo"])


@router.get("/search")
async def search_place(
    q: str = Query(..., description="地名"),
    lat: float | None = Query(None, description="参考纬度"),
    lon: float | None = Query(None, description="参考经度"),
):
    """地名 → 坐标，如果有参考点则附带距离。"""
    result = await geo.geocode(q, ref_lat=lat, ref_lon=lon)
    if result is None:
        return {"success": False, "message": f"找不到地点「{q}」", "data": None}
    return {
        "success": True,
        "data": {
            "name": result.name,
            "lat": result.lat,
            "lon": result.lon,
            "distance_km": result.distance_km,
            "travel_note": result.travel_note,
        },
    }
