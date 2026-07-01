from pydantic import BaseModel, Field


class PositionInput(BaseModel):
    parcelId: str
    latitude: float = Field(..., ge=-90, le=90, description="Latitude WGS-84")
    longitude: float = Field(..., ge=-180, le=180, description="Longitude WGS-84")
