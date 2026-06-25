from pydantic import BaseModel, Field


class PositionInput(BaseModel):
    parcelId: str
    lat: float = Field(..., ge=-90, le=90, description="Latitude WGS-84")
    lng: float = Field(..., ge=-180, le=180, description="Longitude WGS-84")
