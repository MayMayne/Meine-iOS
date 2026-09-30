import XCTest

final class MeineLogicTests: XCTestCase {
    func testPaletteHasTwelveAndIndigo() {
        XCTAssertEqual(Palette12.allHex.count, 12)
        XCTAssertTrue(Palette12.allHex.contains("#4B0082"))
    }

    func testWhiteUsesDarkInkAndBlackUsesLight() {
        let white = RelativeLuminance.value(r: 1, g: 1, b: 1)
        XCTAssertGreaterThan(white, 0.5)
        XCTAssertEqual(RelativeLuminance.ink(luminance: white), .dark)
        let black = RelativeLuminance.value(r: 0, g: 0, b: 0)
        XCTAssertLessThanOrEqual(black, 0.5)
        XCTAssertEqual(RelativeLuminance.ink(luminance: black), .light)
    }

    func testSaturationZeroCollapsesChroma() {
        let color = HSBColor(baseHex: "#FF0000", saturation: 0, brightness: 1)
        let rgb = color.resolvedRGB()
        XCTAssertEqual(rgb.r, rgb.g, accuracy: 0.02)
        XCTAssertEqual(rgb.g, rgb.b, accuracy: 0.02)
    }

    func testBrightnessZeroOnRedIsLightInk() {
        let color = HSBColor(baseHex: "#FF0000", saturation: 1, brightness: 0)
        XCTAssertEqual(RelativeLuminance.ink(for: color), .light)
    }

    func testDeadzoneAndSwipeLock() {
        let zone = EdgeDeadzone.brightnessZone(width: 400)
        XCTAssertEqual(zone.lowerBound, 24)
        XCTAssertEqual(zone.upperBound, 140)
        XCTAssertFalse(EdgeDeadzone.isVerticalLock(dx: 10, dy: 10))
        XCTAssertTrue(EdgeDeadzone.isVerticalLock(dx: 10, dy: 20))
        XCTAssertFalse(EdgeDeadzone.brightnessZone(width: 400).contains(10))
    }

    func testCinemaNinetyPercentRestarts() {
        let snap = ProgressSnapshot(
            ref: MediaRef(sourceID: SourceID(rawValue: "s"), itemID: ItemID(rawValue: "v"), kind: .cinema),
            updatedAt: Date(),
            payload: .cinema(current: .seconds(90), duration: .seconds(100), completed: true)
        )
        XCTAssertEqual(ResumePolicy.decide(snapshot: snap, nowPlayingDuration: .seconds(100)).action, .restart)
    }

    func testCinemaMidwatchToast() {
        let snap = ProgressSnapshot(
            ref: MediaRef(sourceID: SourceID(rawValue: "s"), itemID: ItemID(rawValue: "v"), kind: .cinema),
            updatedAt: Date(),
            payload: .cinema(current: .seconds(65), duration: .seconds(200), completed: false)
        )
        let decision = ResumePolicy.decide(snapshot: snap, nowPlayingDuration: .seconds(200))
        guard case .resume(let from, let toast) = decision.action else {
            return XCTFail("expected resume")
        }
        XCTAssertEqual(from, .seconds(65))
        XCTAssertEqual(toast, "Đã tiếp tục phát từ 01:05")
    }

    func testTimeCodeHour() {
        XCTAssertEqual(TimeCodes.format(3661), "01:01:01")
        XCTAssertEqual(TimeCodes.format(5), "00:05")
    }

    func testChapterSplitAndAnchor() {
        let text = "Mở đầu\n\nChương 1: Hiên\nMột dòng.\n\nChương 2: Mưa\nHai dòng."
        let chapters = HeuristicChapterSplitter.split(text)
        XCTAssertGreaterThanOrEqual(chapters.count, 2)
        let paragraphs = ["aaaa", "bbbb"]
        XCTAssertEqual(CharacterAnchorLock.paragraphIndex(offset: 0, in: paragraphs), 0)
        XCTAssertEqual(CharacterAnchorLock.offsetFor(paragraphIndex: 1, in: paragraphs), 5)
    }

    func testTranslationSkip() {
        let key = TranslationContinue.cacheKey(chapterID: "c1", original: "hello")
        XCTAssertTrue(TranslationContinue.shouldSkip(storyID: "s", chapterID: "c1", original: "hello", cacheKeys: [key]))
        XCTAssertFalse(TranslationContinue.shouldSkip(storyID: "s", chapterID: "c1", original: "other", cacheKeys: [key]))
    }

    func testPhoneticRewrite() {
        XCTAssertEqual(PhoneticMiddleware.rewrite("mình ko dc đi"), "mình không được đi")
    }

    func testTapZones() {
        XCTAssertEqual(TapZoneMap.action(preset: .kindle, x: 360, y: 100, width: 390, height: 844), .next)
        XCTAssertEqual(TapZoneMap.action(preset: .kindle, x: 40, y: 100, width: 390, height: 844), .previous)
        XCTAssertEqual(TapZoneMap.action(preset: .leftRight, x: 200, y: 400, width: 390, height: 844), .menu)
    }

    func testAutoCropShrinksWhiteBorder() {
        let rect = MangaAutoCrop.contentRect(width: 10, height: 10) { x, y in
            x < 2 || y < 2 || x > 7 || y > 7
        }
        XCTAssertGreaterThan(rect.origin.x, 0)
        XCTAssertLessThan(rect.width, 10)
    }

    func testLyricParserAndSleepFade() {
        let lines = LyricParser.parse("[00:01.00] Xin chào\n[00:03.50] Meine")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].text, "Xin chào")
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(SleepFade.gain(now: start, fadeStarted: nil), 1, accuracy: 0.001)
        XCTAssertEqual(SleepFade.gain(now: start.addingTimeInterval(30), fadeStarted: start), 0.5, accuracy: 0.02)
        XCTAssertEqual(SleepFade.gain(now: start.addingTimeInterval(60), fadeStarted: start), 0, accuracy: 0.02)
    }

    func testSourceImportQRAndDrive() {
        let json = #"{"id":"demo","name":"Demo","version":"1","passwordProtected":false,"upstreams":[{"id":"a","kind":"rest","config":{"url":"https://example.com"}}],"mirrors":[],"catalog":[]}"#
        let manifest = try? SourceImporter.importRawJSON(json)
        XCTAssertEqual(manifest?.id.rawValue, "demo")
        let b64 = Data(json.utf8).base64EncodedString()
        XCTAssertEqual(try SourceImporter.importQRPayload(b64).name, "Demo")
        XCTAssertThrowsError(try SourceImporter.importRawJSON("{"))
        XCTAssertEqual(DrivePublicResolver.folderID(from: "https://drive.google.com/drive/folders/abcDEF123"), "abcDEF123")
        XCTAssertEqual(StreamResolver.firstHealthy(preferred: URL(string: "https://a")!, mirrors: [URL(string: "https://b")!], status: { $0.host == "a" ? 403 : 200 })?.host, "b")
        XCTAssertTrue(ETagDecision.isUnchanged(status: 304))
        XCTAssertTrue(ETagDecision.shouldReplace(status: 200))
    }

    func testPasswordAndBackupRoundTrip() throws {
        let salt = Data(repeating: 7, count: 16)
        let stored = SourcePasswordHasher.make(password: "meine", salt: salt)
        XCTAssertTrue(SourcePasswordHasher.verify(password: "meine", stored: stored))
        XCTAssertFalse(SourcePasswordHasher.verify(password: "nope", stored: stored))
        let again = SourcePasswordHasher.make(password: "meine", salt: salt)
        XCTAssertEqual(stored.hash, again.hash)
        let payload = MeineBackupPayload(schema: BackupCodec.schema, sources: [], progress: [], contexts: [], themeHex: "#FFFFFF", saturation: 0, brightness: 1, includeSecrets: false, apiKeyNote: "")
        let data = try BackupCodec.export(payload: payload, pin: "1234")
        let restored = try BackupCodec.restore(data: data, pin: "1234")
        XCTAssertEqual(restored.themeHex, "#FFFFFF")
        XCTAssertThrowsError(try BackupCodec.restore(data: data, pin: "9999"))
    }

    func testAspectFitAndSubtitles() {
        let rect = AspectFitCalculator.fittedRect(video: CGSize(width: 16, height: 9), container: CGSize(width: 19.5, height: 9))
        XCTAssertEqual(rect.height, 9, accuracy: 0.01)
        XCTAssertLessThan(rect.width, 19.5)
        let cues = SubtitleParser.parse("WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nSóng vừa chạm bờ.\n")
        XCTAssertEqual(cues.first?.text, "Sóng vừa chạm bờ.")
        XCTAssertTrue(IntroOutroHint.showIntroSkip(current: 12))
        XCTAssertFalse(IntroOutroHint.showIntroSkip(current: 0.2))
        XCTAssertTrue(IntroOutroHint.inCredits(current: 96, duration: 100))
    }

    func testAI429DoesNotCallSecondHost() async throws {
        let client = AIGatewayClient.shared
        await client.resetTrace()
        await client.setConfig(AIGatewayConfig(provider: .openAICompatible, baseURL: "https://primary.example", model: "m", apiKey: "k"))
        await client.setTransport { _ in
            (429, Data("nope".utf8))
        }
        do {
            _ = try await client.translate(segments: ["hello"], context: .empty(storyID: "s"))
            XCTFail("should throw")
        } catch let error as AIGatewayError {
            XCTAssertEqual(error, .rateLimited(http: 429))
        }
        let hosts = await client.hostsTouched()
        XCTAssertEqual(hosts, ["primary.example"])
    }

    func testShortsPoolCountIsOne() {
        XCTAssertEqual(ShortsPlayerPool.shared.count, 1)
        XCTAssertEqual(ShortsPreloader.cacheKey("abc"), "shorts:abc")
        XCTAssertEqual(ShortsPreloader.byteBudget, 2_000_000)
    }

    func testScraperDoesNotHardcodeDomain() {
        let html = "<a class=\"item\" href=\"/a\">Một</a><a class=\"item\" href=\"/b\">Hai</a>"
        let rows = ScraperUpstream.extract(html: html, rule: ScrapeRule(itemPattern: #"<a class="item" href="([^"]+)">([^<]+)</a>"#, titleGroup: 2, hrefGroup: 1))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].title, "Một")
    }
}
