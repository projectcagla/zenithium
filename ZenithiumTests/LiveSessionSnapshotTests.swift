//
//  LiveSessionSnapshotTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, C10 — what crosses from the watch to the phone.
//
//  A wire format between two processes on two devices, so the tests are about the wire: that
//  it round-trips, that the phone can tell a stale payload from a fresh one, and that ending
//  a session is expressible. None of it needs a paired watch to check.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Live session snapshot")
struct LiveSessionSnapshotTests {

    private let started = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(
        id: UUID = UUID(),
        strain: Double = 11.4,
        progress: Double? = 0.81,
        running: Bool = true,
        generatedAt: Date? = nil
    ) -> LiveSessionSnapshot {
        LiveSessionSnapshot(
            sessionID: id,
            startedAt: started,
            dayStrain: strain,
            ceilingProgress: progress,
            ceiling: 14,
            heartRate: 152,
            band: LiveSessionEngine.band(forProgress: progress),
            isRunning: running,
            generatedAt: generatedAt ?? started.addingTimeInterval(600)
        )
    }

    @Test("Bağlam olarak gidip aynı şekilde geri geliyor")
    func itRoundTripsThroughApplicationContext() throws {
        let original = snapshot()
        let context = try original.asApplicationContext()
        let decoded = try #require(LiveSessionSnapshot.from(applicationContext: context))
        #expect(decoded == original)
    }

    @Test("Bağlam tek bir anahtar taşıyor")
    func thecontextCarriesOneKey() throws {
        let context = try snapshot().asApplicationContext()
        #expect(context.count == 1)
        #expect(context[LiveSessionSnapshot.contextKey] != nil)
        // WCSession takes a property-list dictionary; `Data` is one of the types it allows.
        #expect(context[LiveSessionSnapshot.contextKey] is Data)
    }

    @Test("Başka bir yük sessizce reddediliyor")
    func anunrelatedContextIsRejected() {
        #expect(LiveSessionSnapshot.from(applicationContext: [:]) == nil)
        #expect(LiveSessionSnapshot.from(applicationContext: ["other": 3]) == nil)
        #expect(
            LiveSessionSnapshot.from(
                applicationContext: [LiveSessionSnapshot.contextKey: Data("çöp".utf8)]
            ) == nil
        )
    }

    @Test("Tavansız bir seans da taşınabiliyor")
    func asessionWithoutACeilingCrosses() throws {
        let original = LiveSessionSnapshot(
            sessionID: UUID(),
            startedAt: started,
            dayStrain: 6.2,
            ceilingProgress: nil,
            ceiling: nil,
            heartRate: nil,
            band: .unbounded,
            isRunning: true,
            generatedAt: started
        )
        let decoded = try #require(
            LiveSessionSnapshot.from(applicationContext: try original.asApplicationContext())
        )
        #expect(decoded.ceiling == nil)
        #expect(decoded.ceilingProgress == nil)
        #expect(decoded.heartRate == nil)
        #expect(decoded.band == .unbounded)
    }

    @Test("Biten seans kendini biten olarak taşıyor")
    func afinishedSessionSaysSo() throws {
        let decoded = try #require(
            LiveSessionSnapshot.from(
                applicationContext: try snapshot(running: false).asApplicationContext()
            )
        )
        #expect(!decoded.isRunning)
    }

    @Test("Eski bir yük yenisinden ayırt edilebiliyor")
    func staleAndFreshAreDistinguishable() {
        let id = UUID()
        let older = snapshot(id: id, generatedAt: started.addingTimeInterval(100))
        let newer = snapshot(id: id, generatedAt: started.addingTimeInterval(200))
        // Application context is coalesced and can arrive out of order, which is why the
        // phone compares this rather than trusting arrival order.
        #expect(older.generatedAt < newer.generatedAt)
        #expect(older.sessionID == newer.sessionID)
    }

    @Test("Farklı seanslar farklı kimlik taşıyor")
    func differentSessionsAreDistinguishable() {
        #expect(snapshot().sessionID != snapshot().sessionID)
    }

    @Test("Her bant tel üzerinden geçiyor", arguments: LiveSessionBand.allCases)
    func everyBandCrosses(band: LiveSessionBand) throws {
        let original = LiveSessionSnapshot(
            sessionID: UUID(),
            startedAt: started,
            dayStrain: 10,
            ceilingProgress: 0.5,
            ceiling: 14,
            heartRate: 140,
            band: band,
            isRunning: true,
            generatedAt: started
        )
        let decoded = try #require(
            LiveSessionSnapshot.from(applicationContext: try original.asApplicationContext())
        )
        #expect(decoded.band == band)
    }
}
