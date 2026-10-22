import CryptoKit
import ImageIO
import XCTest
@testable import FramePlay

final class DecoderTests: XCTestCase {
    func testRealWebPMetadataAndBoundedDistinctFrames() throws {
        let decoder = try ImageIODecoder(data: TestFixtures.webP(), configuration: PlaybackConfiguration(maximumPixelSize: 160))
        XCTAssertEqual(decoder.metadata.frameCount, 25)
        XCTAssertEqual(decoder.metadata.pixelWidth, 640)
        XCTAssertNil(decoder.metadata.totalPlayCount)
        XCTAssertEqual(decoder.metadata.duration, 3, accuracy: 0.000_001)
        var hashes = Set<SHA256.Digest>()
        for index in [0, 12, 24] {
            let frame = try decoder.frame(at: index)
            XCTAssertEqual(frame.width, 160)
            XCTAssertEqual(frame.height, 160)
            let bytes = try XCTUnwrap(frame.dataProvider?.data) as Data
            hashes.insert(SHA256.hash(data: bytes))
        }
        XCTAssertEqual(hashes.count, 3)
    }

    func testGIFUsesIndividualDelaysAndNormalizesRepeats() throws {
        let decoder = try ImageIODecoder(data: TestFixtures.encoded(loops: 1), configuration: PlaybackConfiguration())
        XCTAssertEqual(decoder.metadata.frameDurations, [0.1, 0.2, 0.3])
        XCTAssertEqual(decoder.metadata.totalPlayCount, 2)
    }

    func testAPNGUsesTotalPlayCountAndPreservesAlpha() throws {
        let decoder = try ImageIODecoder(data: TestFixtures.encoded(type: "public.png", loops: 2), configuration: PlaybackConfiguration())
        XCTAssertEqual(decoder.metadata.frameCount, 3)
        XCTAssertEqual(decoder.metadata.totalPlayCount, 2)
        let image = try decoder.frame(at: 2)
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertGreaterThan(data[3], 100)
        XCTAssertLessThan(data[3], 200)
    }

    func testStaticPNGAndMalformedData() throws {
        let decoder = try ImageIODecoder(data: TestFixtures.encoded(type: "public.png", delays: [0.1]), configuration: PlaybackConfiguration())
        XCTAssertEqual(decoder.metadata.frameCount, 1)
        XCTAssertThrowsError(try ImageIODecoder(data: Data("broken".utf8), configuration: PlaybackConfiguration()))
        XCTAssertThrowsError(try decoder.frame(at: 5))
    }

    func testInputAndCanvasLimitsApplyBeforeFrameDecode() throws {
        let data = try TestFixtures.encoded()
        var configuration = PlaybackConfiguration()
        configuration.limits.maximumDataBytes = 1
        XCTAssertThrowsError(try ImageIODecoder(data: data, configuration: configuration)) { XCTAssertEqual($0 as? PlaybackFailure, .resourceLimitExceeded) }
        configuration = PlaybackConfiguration()
        configuration.limits.maximumCanvasPixels = 1
        XCTAssertThrowsError(try ImageIODecoder(data: data, configuration: configuration)) { XCTAssertEqual($0 as? PlaybackFailure, .resourceLimitExceeded) }
        configuration = PlaybackConfiguration()
        configuration.limits.maximumFrameCount = 2
        XCTAssertThrowsError(try ImageIODecoder(data: data, configuration: configuration)) { XCTAssertEqual($0 as? PlaybackFailure, .resourceLimitExceeded) }
    }
}
