module LongBridgeTimeZonesExt

import Dates: DateTime, unix2datetime
using TimeZones
import LongBridge: to_market_time

const UTC_TIME_ZONE = TimeZone("UTC")

_as_utc(timestamp::DateTime) = ZonedDateTime(timestamp, UTC_TIME_ZONE)
_as_utc(timestamp::Integer) = _as_utc(unix2datetime(timestamp))

to_market_time(timestamp::Union{DateTime,Integer}, timezone::TimeZone) =
    astimezone(_as_utc(timestamp), timezone)

to_market_time(timestamp::Union{DateTime,Integer}, timezone::AbstractString) =
    to_market_time(timestamp, TimeZone(String(timezone)))

to_market_time(timestamp::ZonedDateTime, timezone::TimeZone) =
    astimezone(timestamp, timezone)

to_market_time(timestamp::ZonedDateTime, timezone::AbstractString) =
    to_market_time(timestamp, TimeZone(String(timezone)))

end # module LongBridgeTimeZonesExt
