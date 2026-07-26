import XCTest

@MainActor
final class HibroUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInboxRunAndResourceNavigation() {
        launchApp()
        XCTAssertTrue(
            app.staticTexts["需要你的决定"].waitForExistence(timeout: 8)
        )

        openSection("收件箱")
        XCTAssertTrue(
            app.navigationBars["收件箱"].waitForExistence(timeout: 4)
        )
        app.staticTexts["部署 Core 更新"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["事项详情"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["做出决定"].exists)
        goBack()

        openSection("运行")
        XCTAssertTrue(
            app.navigationBars["运行"].waitForExistence(timeout: 4)
        )
        app.staticTexts[
            "整理 Hibro App 第一版需要完成的功能与优先级"
        ].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["运行详情"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["概览"].exists)
        XCTAssertTrue(app.buttons["时间线"].exists)
        XCTAssertTrue(app.buttons["对话"].exists)
        XCTAssertTrue(app.buttons["产出"].exists)
        XCTAssertTrue(app.staticTexts["执行流程"].exists)
        XCTAssertTrue(app.staticTexts["协作"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["结果"].exists)
        goBack()

        openSection("更多")
        XCTAssertTrue(
            app.navigationBars["更多"].waitForExistence(timeout: 4)
        )
        app.staticTexts["Agents"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["Agents"].waitForExistence(timeout: 4)
        )
    }

    func testHomeCanScrollThroughAllSections() {
        launchApp()
        XCTAssertTrue(
            app.staticTexts["需要你的决定"].waitForExistence(timeout: 8)
        )
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(
            app.staticTexts["系统状态"].waitForExistence(timeout: 4)
        )
    }

    func testLandscapePrimaryNavigation() {
        launchApp()
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock {
            XCUIDevice.shared.orientation = .portrait
        }

        XCTAssertTrue(
            app.staticTexts["需要你的决定"].waitForExistence(timeout: 8)
        )
        openSection("收件箱")
        XCTAssertTrue(
            app.navigationBars["收件箱"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["部署 Core 更新"].firstMatch.exists)
    }

    func testDarkModeVisualHierarchy() {
        launchApp()
        XCTAssertTrue(
            app.staticTexts["需要你的决定"].waitForExistence(timeout: 8)
        )
        capture("dark-home")

        openSection("收件箱")
        app.staticTexts["部署 Core 更新"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts["做出决定"].waitForExistence(timeout: 4)
        )
        scrollToHittable(app.buttons["仅本次允许"])
        XCTAssertTrue(app.buttons["拒绝"].isHittable)
        XCTAssertTrue(app.buttons["仅本次允许"].isHittable)
        XCTAssertTrue(app.buttons["本会话允许"].isHittable)
        capture("dark-approval")
    }

    func testConversationPinsApprovalAboveComposer() {
        launchApp()
        openSection("更多")
        app.staticTexts["对话"].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["对话"].waitForExistence(timeout: 4)
        )
        app.staticTexts["检查 Core 部署状态"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["Agent 正在等待你的决定"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["仅本次"].isHittable)
        XCTAssertTrue(app.buttons["本会话"].isHittable)
        XCTAssertTrue(app.buttons["拒绝"].isHittable)
    }

    func testCompactSplitWidthWorkflow() throws {
        launchApp()
        try requireIPad()
        relaunch(viewportWidth: 430)

        XCTAssertTrue(
            app.staticTexts["需要你的决定"].waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.tabBars.firstMatch.exists)
        capture("split-compact-home")

        openSection("运行")
        app.staticTexts[
            "整理 Hibro App 第一版需要完成的功能与优先级"
        ].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["运行详情"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["执行流程"].exists)
        capture("split-compact-run")
    }

    func testRunDetailInformationSections() {
        launchApp()
        openSection("运行")
        app.staticTexts[
            "整理 Hibro App 第一版需要完成的功能与优先级"
        ].firstMatch.tap()
        XCTAssertTrue(
            app.navigationBars["运行详情"].waitForExistence(timeout: 4)
        )

        app.buttons["时间线"].tap()
        XCTAssertTrue(
            app.staticTexts["还没有运行事件"].waitForExistence(timeout: 4)
        )

        app.buttons["对话"].tap()
        XCTAssertTrue(
            app.staticTexts["关联对话"].waitForExistence(timeout: 4)
        )

        app.buttons["产出"].tap()
        XCTAssertTrue(
            app.staticTexts["还没有产出"].waitForExistence(timeout: 4)
        )
        capture("run-detail-sections")
    }

    func testRegularSplitWidthWorkflow() throws {
        launchApp()
        try requireIPad()
        relaunch(viewportWidth: 680)

        XCTAssertTrue(
            app.staticTexts["需要你的决定"].waitForExistence(timeout: 8)
        )
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        capture("split-regular-home")

        openSection("收件箱")
        XCTAssertTrue(
            app.navigationBars["收件箱"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["部署 Core 更新"].firstMatch.exists)
    }

    private func launchApp(arguments: [String] = ["-hibro-demo"]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private func relaunch(viewportWidth: Int) {
        app.terminate()
        launchApp(
            arguments: [
                "-hibro-demo",
                "-hibro-qa-viewport-width",
                "\(viewportWidth)",
            ]
        )
    }

    private func requireIPad() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        if min(window.frame.width, window.frame.height) < 700 {
            throw XCTSkip("iPad 分屏场景只在 iPad 模拟器运行")
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollToHittable(_ element: XCUIElement) {
        for _ in 0..<3 where !element.isHittable {
            app.swipeUp()
        }
    }

    private func openSection(_ label: String) {
        let tabButton = app.tabBars.buttons[label]
        if tabButton.exists {
            tabButton.tap()
            return
        }
        let sidebarButton = app.buttons[label].firstMatch
        if sidebarButton.waitForExistence(timeout: 2) {
            sidebarButton.tap()
            return
        }
        let sidebarLabel = app.staticTexts[label].firstMatch
        XCTAssertTrue(
            sidebarLabel.waitForExistence(timeout: 4),
            "找不到导航入口：\(label)"
        )
        sidebarLabel.tap()
    }

    private func goBack() {
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 4))
        backButton.tap()
    }
}
