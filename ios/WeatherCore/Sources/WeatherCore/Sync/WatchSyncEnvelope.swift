import Foundation

/// Wire format for WatchConnectivity application context (§9.2).
///
/// The payload is JSON `Data` under a single key rather than a loose dictionary,
/// so the schema is versioned and typed on both sides.
public enum WatchSyncEnvelope {
    public static let payloadKey = "payload"
    public static let versionKey = "version"
    public static let currentVersion = 1

    /// How far the synced normals may be from the watch's own location before
    /// they stop describing the same place (§9.2, §14.8).
    public static let maximumNormalsDistance: Double = 25_000  // metres

    public static func encode(_ payload: WatchSyncPayload) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return [
            versionKey: currentVersion,
            payloadKey: try encoder.encode(payload)
        ]
    }

    public static func decode(_ context: [String: Any]) -> WatchSyncPayload? {
        guard let version = context[versionKey] as? Int, version == currentVersion,
              let data = context[payloadKey] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WatchSyncPayload.self, from: data)
    }

    /// Whether a synced payload may be used for `location`.
    ///
    /// Normals from another city are worse than no normals: they would silently
    /// produce a confident, wrong anomaly badge.
    public static func isApplicable(
        _ payload: WatchSyncPayload, to location: WeatherLocation
    ) -> Bool {
        payload.location.distance(to: location) <= maximumNormalsDistance
    }
}

extension WatchSyncPayload {
    /// Rebuilds the `TempBand` the anomaly engine expects from the synced arrays.
    public var tempBand: TempBand? {
        guard dailyAvg.count == 14 else { return nil }
        return TempBand(
            dailyAvg: dailyAvg, month: "", histYearStart: 0, histYearEnd: 0)
    }

    /// Rebuilds the hourly wet-bulb normals used by the mugginess badge.
    public var wetBulbNormals: HourAverages? {
        guard wbAvgByHour.count == 24 else { return nil }
        return HourAverages(avgByHour: wbAvgByHour, yearStart: 0, yearEnd: 0)
    }

    public init(
        location: WeatherLocation,
        imperial: Bool,
        tempBand: TempBand?,
        climatology: Climatology?,
        hourlyNormals: HourlyNormals?,
        generatedAt: Date = Date()
    ) {
        self.init(
            latitude: location.latitude,
            longitude: location.longitude,
            name: location.name,
            imperial: imperial,
            dailyAvg: tempBand?.dailyAvg ?? [],
            monthlyNormals: climatology?.months ?? [],
            wbAvgByHour: hourlyNormals?.wetBulb.avgByHour ?? [],
            generatedAt: generatedAt)
    }

    /// Nothing useful to send yet.
    public var isEmpty: Bool {
        dailyAvg.isEmpty && monthlyNormals.isEmpty && wbAvgByHour.isEmpty
    }
}
