import XCTest
@testable import UpkeepKit

/// The gate that decides what may be touched.
///
/// This is the most dangerous code in the app: everything the cleaner, the
/// scanner and the uninstaller propose passes through it, and a mistake here
/// costs someone their files. It is pure logic over strings, so it can be
/// tested exhaustively without going near the disk.
final class SafetyTests: XCTestCase {

    private var home: String { NSHomeDirectory() }

    // MARK: Scanning

    func testSystemRootsAreNeverScanned() {
        for root in ["/System", "/usr", "/bin", "/sbin", "/Volumes", "/dev",
                     "/private/var/db", "/Library/Apple", "/net", "/.vol"] {
            XCTAssertFalse(Safety.mayScan(root), "\(root) taranabilir görünüyor")
            XCTAssertFalse(Safety.mayScan(root + "/altinda/bir/sey"),
                           "\(root) altı taranabilir görünüyor")
        }
    }

    /// A forbidden root must not shadow a different directory that merely
    /// starts with the same letters.
    func testPrefixDoesNotLeakToNeighbours() {
        XCTAssertTrue(Safety.mayScan("/Systems"))
        XCTAssertTrue(Safety.mayScan("/usr2"))
        XCTAssertTrue(Safety.mayScan("\(home)/Volumes"))
    }

    func testHomeIsScannable() {
        XCTAssertTrue(Safety.mayScan(home))
        XCTAssertTrue(Safety.mayScan("\(home)/Library/Caches"))
    }

    // MARK: Deleting

    /// The user's own folders are scanned — their size is shown — but can never
    /// be proposed for deletion. A cleaner that offers to empty the Desktop is
    /// the moment the tool becomes the damage.
    func testProtectedFoldersCannotBeDeleted() {
        for path in [home,
                     "\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads",
                     "\(home)/Pictures", "\(home)/Movies", "\(home)/Music",
                     "\(home)/Library", "\(home)/Library/Mobile Documents",
                     "/Applications", "/Users", "/Library"] {
            XCTAssertFalse(Safety.mayDelete(path), "\(path) silinebilir görünüyor")
        }
    }

    /// The *contents* of a protected folder are a different matter: a cache
    /// inside `~/Library` is exactly what the cleaner is for.
    func testInsideProtectedFoldersIsAllowed() {
        XCTAssertTrue(Safety.mayDelete("\(home)/Library/Caches/com.example.app"))
        XCTAssertTrue(Safety.mayDelete("\(home)/Documents/eski-proje/node_modules"))
        XCTAssertTrue(Safety.mayDelete("\(home)/Downloads/kurulum.dmg"))
    }

    func testOutsideHomeIsRefused() {
        XCTAssertFalse(Safety.mayDelete("/tmp/bir-sey"))
        XCTAssertFalse(Safety.mayDelete("/Library/Caches/com.example.app"))
        XCTAssertFalse(Safety.mayDelete("/Users/baskasi/Documents/rapor.pdf"))
    }

    /// `..` must not walk out of the home directory.
    func testRelativeEscapeIsRefused() {
        XCTAssertFalse(Safety.mayDelete("\(home)/Library/../../../etc/hosts"))
        XCTAssertFalse(Safety.mayDelete("\(home)/.."))
    }

    /// `standardizingPath` resolves a tilde, so the two spellings of the same
    /// path have to reach the same verdict.
    func testTildeAndAbsoluteAgree() {
        XCTAssertEqual(Safety.mayDelete("~/Library/Caches/x"),
                       Safety.mayDelete("\(home)/Library/Caches/x"))
        XCTAssertFalse(Safety.mayDelete("~"))
        XCTAssertFalse(Safety.mayDelete("~/Documents"))
    }

    // MARK: Uninstalling

    /// The uninstaller needs a door `mayDelete` deliberately does not open:
    /// its whole subject is a bundle in /Applications.
    func testApplicationBundlesAreDeletableThroughTheirOwnGate() {
        XCTAssertTrue(Safety.mayDeleteApp("/Applications/Bir Uygulama.app"))
        XCTAssertTrue(Safety.mayDeleteApp("\(home)/Applications/Bir Uygulama.app"))
        XCTAssertTrue(Safety.mayDeleteApp("/Applications/Utilities/Bir Uygulama.app"))
    }

    func testAppleApplicationsAreNotTouchable() {
        // /System/Applications sits under a forbidden root.
        XCTAssertFalse(Safety.mayDeleteApp("/System/Applications/Safari.app"))
        XCTAssertFalse(Safety.mayDeleteApp("/System/Applications/Utilities/Terminal.app"))
    }

    func testOnlyBundlesPassTheAppGate() {
        XCTAssertFalse(Safety.mayDeleteApp("/Applications"))
        XCTAssertFalse(Safety.mayDeleteApp("/Applications/bir-dosya.txt"))
        XCTAssertFalse(Safety.mayDeleteApp("\(home)/Desktop/Sahte.app"))
    }

    /// The two gates stay separate: a bundle is not deletable through the
    /// ordinary path, so a stray click in the disk view cannot remove an app.
    func testDiskViewCannotRemoveApplications() {
        XCTAssertFalse(Safety.mayDelete("/Applications/Bir Uygulama.app"))
    }

    // MARK: Trash

    func testRefusedPathThrowsRatherThanActing() {
        XCTAssertThrowsError(try Safety.moveToTrash(URL(fileURLWithPath: "/System/Library"))) { error in
            guard case Safety.SafetyError.refused = error else {
                return XCTFail("beklenen ret hatası değil: \(error)")
            }
        }
        XCTAssertThrowsError(try Safety.moveToTrash(URL(fileURLWithPath: home)))
        // An app bundle needs the flag; without it the ordinary gate refuses.
        XCTAssertThrowsError(try Safety.moveToTrash(URL(fileURLWithPath: "/Applications/Bir Uygulama.app")))
    }

    /// Only the Trash may be emptied, and only through its own gate.
    func testTrashGateAcceptsOnlyTheTrash() {
        XCTAssertTrue(Safety.isTrash("\(home)/.Trash"))
        XCTAssertTrue(Safety.isTrash("~/.Trash"))
        XCTAssertFalse(Safety.isTrash("\(home)/.Trash/icindeki"))
        XCTAssertFalse(Safety.isTrash("\(home)/Documents"))
        XCTAssertFalse(Safety.isTrash("/Volumes/Yedek/.Trashes"))
        XCTAssertFalse(Safety.isTrash("/Users/baskasi/.Trash"))
    }

    /// Permanent deletion exists in exactly one place — emptying the Trash,
    /// because a folder cannot be moved inside itself — and that place is
    /// guarded. Everything else goes to the Trash, which the person can undo.
    ///
    /// The test reads the sources because the rule is about the module as a
    /// whole: a future `removeItem` added anywhere else would be a silent
    /// change from "recoverable" to "gone".
    func testPermanentDeletionOnlyWhereTheTrashIsEmptied() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")

        let files = (FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }) ?? []
        XCTAssertFalse(files.isEmpty, "kaynak bulunamadı")

        var callers: [String] = []
        for file in files where try String(contentsOf: file, encoding: .utf8).contains("removeItem") {
            callers.append(file.lastPathComponent)
        }
        XCTAssertEqual(callers, ["CleanupService.swift"],
                       "kalıcı silme yalnız çöp kutusu boşaltmada olmalı")

        let cleanup = try String(contentsOf: sources
            .appendingPathComponent("UpkeepKit/Core/CleanupService.swift"), encoding: .utf8)
        XCTAssertTrue(cleanup.contains("Safety.isTrash"),
                      "çöp kutusu boşaltma kapısız kalmış")
    }
}
