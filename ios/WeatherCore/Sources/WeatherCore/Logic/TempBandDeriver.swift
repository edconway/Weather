import Foundation

/// The 14-day rolling normal band (§6.4) — a port of `deriveTempBand`.
///
/// For each day offset −7…+6 from today, pools every archive value whose
/// calendar day is within 3 days of it (`MMDD.distance <= 3`), then averages.
/// Index 7 is today.
public enum TempBandDeriver {

    public static func derive(
        climatology: Climatology, now: Date, timeZone: TimeZone
    ) -> TempBand {
        let dateKit = DateKit(timeZone: timeZone)
        let pools = Array(climatology.byMMDD)

        var dailyAvg: [DayNormal] = []
        dailyAvg.reserveCapacity(14)

        for offset in -7...6 {
            let mmdd = dateKit.monthDayString(offsetDays: offset, from: now)
            var maxes: [Double] = []
            var mins: [Double] = []
            var wbMaxes: [Double] = []
            var wbMins: [Double] = []

            for (poolMMDD, pool) in pools where MMDD.distance(mmdd, poolMMDD) <= 3 {
                maxes.append(contentsOf: pool.maxes)
                mins.append(contentsOf: pool.mins)
                wbMaxes.append(contentsOf: pool.wbMaxes)
                wbMins.append(contentsOf: pool.wbMins)
            }

            dailyAvg.append(DayNormal(
                tMax: Stats.mean(maxes),
                tMin: Stats.mean(mins),
                wbMax: Stats.mean(wbMaxes),
                wbMin: Stats.mean(wbMins)))
        }

        var monthStyle = Date.FormatStyle().month(.wide)
        monthStyle.timeZone = timeZone
        monthStyle.locale = Locale(identifier: "en_US")

        return TempBand(
            dailyAvg: dailyAvg,
            month: now.formatted(monthStyle),
            histYearStart: climatology.yearStart,
            histYearEnd: climatology.yearEnd)
    }
}
