//
//  LiveSessionOutboxTests.swift
//  ZenithiumTests
//
//  What the watch owes the phone when the two are not talking.
//
//  The failure being guarded against is specific and visible: a Live Activity that never
//  hears `isRunning: false` keeps running on a phone after the session ended. Everything
//  here is about that one payload surviving where the others are allowed not to.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Live session outbox")
struct LiveSessionOutboxTests {

    private let sessionID = UUID()
    private let startedAt = Date(timeIntervalSince1970: 1_760_000_000)

    private func snapshot(
        strain: Double,
        running: Bool,
        at offset: TimeInterval,
        session: UUID? = nil
    ) -> LiveSessionSnapshot {
        LiveSessionSnapshot(
            sessionID: session ?? sessionID,
            startedAt: startedAt,
            dayStrain: strain,
            ceilingProgress: strain / 15,
            ceiling: 15,
            heartRate: 150,
            band: .building,
            isRunning: running,
            generatedAt: startedAt.addingTimeInterval(offset)
        )
    }

    // MARK: - Frames

    @Test("Kareler birikmiyor, en yenisi öncekinin yerini alıyor")
    func framesCoalesce() {
        var outbox = LiveSessionOutbox()
        for second in 1...50 {
            outbox.hold(snapshot(strain: Double(second) / 10, running: true, at: Double(second)))
        }
        #expect(outbox.snapshotsToSend.count == 1)
        #expect(outbox.pendingFrame?.dayStrain == 5)
    }

    @Test("Geç gelen eski kare, yenisinin yerini almıyor")
    func anOlderFrameDoesNotDisplaceANewerOne() {
        var outbox = LiveSessionOutbox()
        outbox.hold(snapshot(strain: 9, running: true, at: 100))
        outbox.hold(snapshot(strain: 3, running: true, at: 40))
        #expect(outbox.pendingFrame?.dayStrain == 9)
    }

    // MARK: - The terminal snapshot

    /// The one payload whose loss somebody notices.
    @Test("Bitiş anlık görüntüsü sabitleniyor ve önce gönderiliyor")
    func theTerminalSnapshotIsPinnedAndLeads() {
        var outbox = LiveSessionOutbox()
        outbox.hold(snapshot(strain: 8, running: true, at: 100))
        outbox.hold(snapshot(strain: 11, running: false, at: 200))

        let toSend = outbox.snapshotsToSend
        #expect(toSend.count == 1)
        #expect(toSend.first?.isRunning == false)
        #expect(toSend.first?.dayStrain == 11)
        // A session that has ended has no running frame worth sending.
        #expect(outbox.pendingFrame == nil)
    }

    @Test("Bitişten sonra gelen kare, bitişi silmiyor")
    func aLateFrameCannotEraseTheEnding() {
        var outbox = LiveSessionOutbox()
        outbox.hold(snapshot(strain: 11, running: false, at: 200))
        // Coalesced delivery can hand back a frame recorded before the end.
        outbox.hold(snapshot(strain: 10, running: true, at: 190))

        #expect(outbox.pendingTerminal?.dayStrain == 11)
        #expect(outbox.snapshotsToSend.contains { !$0.isRunning })
    }

    @Test("Gönderilenler temizlenince kutu boşalıyor")
    func clearingEmptiesTheSnapshots() {
        var outbox = LiveSessionOutbox()
        outbox.hold(snapshot(strain: 11, running: false, at: 200))
        outbox.clearSnapshots()
        #expect(outbox.snapshotsToSend.isEmpty)
        #expect(outbox.isEmpty)
    }

    // MARK: - The sample backlog

    @Test("Örnek tamponu sınırlı ve düşenleri sayıyor")
    func theSampleBufferIsBoundedAndCounts() {
        var outbox = LiveSessionOutbox()
        let overflow = 500
        let total = LiveSessionOutbox.maximumBufferedSamples + overflow
        for index in 0..<total {
            outbox.hold(sample: LiveHeartRateSample(
                elapsedSeconds: Double(index),
                beatsPerMinute: 150
            ))
        }

        #expect(outbox.bufferedSamples.count == LiveSessionOutbox.maximumBufferedSamples)
        #expect(outbox.droppedSampleCount == overflow)
        // The newest samples are the ones kept.
        #expect(outbox.bufferedSamples.first?.elapsedSeconds == Double(overflow))
        #expect(outbox.bufferedSamples.last?.elapsedSeconds == Double(total - 1))
    }

    @Test("Tamponu almak kutuyu boşaltıyor ve eksikliği bildiriyor")
    func takingTheBatchReportsWhatWasLost() throws {
        var outbox = LiveSessionOutbox()
        for index in 0..<(LiveSessionOutbox.maximumBufferedSamples + 10) {
            outbox.hold(sample: LiveHeartRateSample(
                elapsedSeconds: Double(index),
                beatsPerMinute: 150
            ))
        }

        let taken = outbox.takeSamples()
        let batch = try #require(taken)
        #expect(batch.droppedCount == 10)
        #expect(!batch.isComplete, "eksik bir tekrar oynatma tam sayılmamalı")
        #expect(outbox.bufferedSamples.isEmpty)
        #expect(outbox.droppedSampleCount == 0)
        #expect(outbox.takeSamples() == nil)
    }

    @Test("Kesintisiz bir tampon tam olarak işaretleniyor")
    func anUninterruptedBatchIsComplete() throws {
        var outbox = LiveSessionOutbox()
        for index in 0..<100 {
            outbox.hold(sample: LiveHeartRateSample(
                elapsedSeconds: Double(index),
                beatsPerMinute: 140
            ))
        }
        let taken = outbox.takeSamples()
        let batch = try #require(taken)
        #expect(batch.isComplete)
        #expect(batch.samples.count == 100)
    }

    // MARK: - The wire

    @Test("Örnek yığını sözlüğe gidip geri dönüyor")
    func theBatchSurvivesTheWire() throws {
        var batch = LiveSessionSampleBatch(
            samples: (0..<50).map {
                LiveHeartRateSample(elapsedSeconds: Double($0), beatsPerMinute: 140 + Double($0))
            },
            droppedCount: 7
        )
        batch.sessionID = sessionID
        batch.startedAt = startedAt

        let userInfo = try batch.asUserInfo()
        let restored = try #require(LiveSessionSampleBatch.from(userInfo: userInfo))

        #expect(restored == batch)
        #expect(restored.sessionID == sessionID)
        #expect(restored.droppedCount == 7)
        #expect(restored.samples.count == 50)
    }

    @Test("Tanınmayan yük çözülmüyor")
    func anUnrelatedPayloadIsRejected() {
        #expect(LiveSessionSampleBatch.from(userInfo: ["baska": 1]) == nil)
        #expect(LiveSessionSampleBatch.from(userInfo: [:]) == nil)
    }

    // MARK: - Boyut

    /// The measurement the chunk size is set from, asserted rather than trusted.
    ///
    /// WatchConnectivity refuses a payload over 65.536 bayt and reports it through a delegate
    /// callback the app does not implement — so an oversize backlog looked like a successful
    /// send and delivered nothing. This is the test that notices if the encoding gets wider.
    @Test("Bir aktarım WatchConnectivity bütçesinin altında kalıyor")
    func oneTransferFitsInsideTheBudget() throws {
        // Stamped late in a session on purpose: `elapsedSeconds` encodes wider as it grows,
        // so a chunk measured from zero understates the worst case by about a kilobyte.
        var batch = LiveSessionSampleBatch(
            samples: (0..<LiveSessionSampleBatch.maximumSamplesPerTransfer).map {
                LiveHeartRateSample(
                    elapsedSeconds: 14_000 + Double($0) + 0.123456,
                    beatsPerMinute: 120 + Double($0 % 60)
                )
            },
            droppedCount: 0
        )
        batch.sessionID = sessionID
        batch.startedAt = startedAt
        batch.chunkIndex = 9
        batch.chunkCount = 10

        let payload = try #require(try batch.asUserInfo()[LiveSessionSampleBatch.userInfoKey] as? Data)
        #expect(payload.count < 65_536 / 2, "aktarım \(payload.count) bayt — bütçenin yarısını aştı")
    }

    @Test("Sığmayan yığın parçalara bölünüyor, örnek kaybı olmadan")
    func anOversizeBacklogIsSplitWithoutLoss() throws {
        let total = LiveSessionSampleBatch.maximumSamplesPerTransfer * 2 + 37
        var batch = LiveSessionSampleBatch(
            samples: (0..<total).map {
                LiveHeartRateSample(elapsedSeconds: Double($0), beatsPerMinute: 140)
            },
            droppedCount: 11
        )
        batch.sessionID = sessionID
        batch.startedAt = startedAt

        let chunks = batch.chunked()
        #expect(chunks.count == 3)
        #expect(chunks.map(\.samples.count).reduce(0, +) == total)
        #expect(chunks.flatMap(\.samples) == batch.samples, "sıra veya içerik bozuldu")

        // The dropped count describes the backlog, so exactly one chunk carries it.
        #expect(chunks.map(\.droppedCount).reduce(0, +) == 11)
        #expect(chunks[0].droppedCount == 11)

        for (index, chunk) in chunks.enumerated() {
            #expect(chunk.chunkIndex == index)
            #expect(chunk.chunkCount == 3)
            #expect(chunk.sessionID == sessionID)
            #expect(chunk.startedAt == startedAt)
            #expect(chunk.isFinalChunk == (index == 2))
        }
    }

    @Test("Sığan yığın bölünmüyor")
    func abacklogThatFitsIsSentWhole() {
        let batch = LiveSessionSampleBatch(
            samples: (0..<10).map { LiveHeartRateSample(elapsedSeconds: Double($0), beatsPerMinute: 140) },
            droppedCount: 0
        )
        let chunks = batch.chunked()
        #expect(chunks.count == 1)
        #expect(chunks[0].chunkCount == 1)
        #expect(chunks[0].isFinalChunk)
    }

    // MARK: - Geri koyma

    /// `takeSamples()` empties the buffer before the caller knows the transfer went. The one
    /// failure path used to drop the whole backlog, silently, in the type whose job is not
    /// doing that.
    @Test("Gönderilemeyen yığın kutuya geri konuyor")
    func anUndeliveredBacklogGoesBack() throws {
        var outbox = LiveSessionOutbox()
        for index in 0..<5 {
            outbox.hold(sample: LiveHeartRateSample(elapsedSeconds: Double(index), beatsPerMinute: 150))
        }
        let sampleBatch = outbox.takeSamples()
        let taken = try #require(sampleBatch)
        #expect(outbox.bufferedSamples.isEmpty)

        outbox.restore(samples: taken.samples, droppedCount: taken.droppedCount)
        #expect(outbox.bufferedSamples == taken.samples, "geri konan örnekler sırasını korumalı")
        #expect(outbox.droppedSampleCount == taken.droppedCount)
    }

    @Test("Geri konan yığın sırayı ve tavanı koruyor")
    func restoringKeepsOrderAndTheCap() {
        var outbox = LiveSessionOutbox()
        // Newer samples arrived while the older ones were in flight.
        for index in 10..<15 {
            outbox.hold(sample: LiveHeartRateSample(elapsedSeconds: Double(index), beatsPerMinute: 150))
        }
        let older = (0..<5).map { LiveHeartRateSample(elapsedSeconds: Double($0), beatsPerMinute: 150) }
        outbox.restore(samples: older, droppedCount: 3)

        #expect(outbox.bufferedSamples.count == 10)
        #expect(outbox.bufferedSamples.first?.elapsedSeconds == 0, "eskiler öne konmalı")
        #expect(outbox.bufferedSamples.last?.elapsedSeconds == 14)
        #expect(outbox.droppedSampleCount == 3)
    }

    @Test("Boş bir geri koyma hiçbir şey değiştirmiyor")
    func restoringNothingChangesNothing() {
        var outbox = LiveSessionOutbox()
        outbox.hold(sample: LiveHeartRateSample(elapsedSeconds: 1, beatsPerMinute: 150))
        outbox.restore(samples: [], droppedCount: 4)
        #expect(outbox.bufferedSamples.count == 1)
        #expect(outbox.droppedSampleCount == 0)
    }

    @Test("Boş kutu boş")
    func anEmptyOutboxIsEmpty() {
        let outbox = LiveSessionOutbox()
        #expect(outbox.isEmpty)
        #expect(outbox.snapshotsToSend.isEmpty)
    }
}
