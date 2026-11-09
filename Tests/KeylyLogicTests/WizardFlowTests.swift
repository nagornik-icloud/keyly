import Testing
@testable import KeylyLogic

/// The permissions step lock fails SILENTLY: a wrong condition does not crash, it just lets
/// the user through, and then the product does not work and the user does not know why.
struct WizardFlowTests {

    private let all = WizardFlow.steps(localModelAvailable: true)
    private let noModel = WizardFlow.steps(localModelAvailable: false)

    @Test("Шаг модели исключается, пока фичи нет в сборке")
    func modelStepHiddenWhenUnavailable() {
        #expect(noModel.contains(.model) == false, "экран «скачайте модель» без возможности скачать — ложь")
        #expect(all.contains(.model))
        #expect(noModel.count == all.count - 1)
    }

    @Test("Порядок шагов сохраняется и начинается с приветствия")
    func stepOrder() {
        #expect(all == [.hello, .permissions, .model, .hotkeys, .done, .more])
        #expect(noModel == [.hello, .permissions, .hotkeys, .done, .more])
    }

    // MARK: - Permissions step lock

    @Test("Шаг прав блокирует ТОЛЬКО Accessibility")
    func permissionsBlockOnAccessibilityOnly() {
        #expect(!WizardFlow.canAdvance(from: .permissions, accessibilityGranted: false, microphoneGranted: false))
        #expect(!WizardFlow.canAdvance(from: .permissions, accessibilityGranted: false, microphoneGranted: true),
                "без Accessibility не работает НИ ОДНА текстовая фича")
        #expect(WizardFlow.canAdvance(from: .permissions, accessibilityGranted: true, microphoneGranted: false),
                "микрофон нужен одному модулю из пяти — блокировать им визард нельзя")
        #expect(WizardFlow.canAdvance(from: .permissions, accessibilityGranted: true, microphoneGranted: true))
    }

    @Test("Остальные шаги не блокируются правами")
    func otherStepsNeverBlock() {
        for step in WizardStep.allCases where step != .permissions {
            #expect(WizardFlow.canAdvance(from: step, accessibilityGranted: false, microphoneGranted: false),
                    "шаг \(step.rawValue) не должен блокироваться правами")
        }
    }

    // MARK: - Navigation

    @Test("Переход вперёд идёт по ТЕКУЩЕМУ набору, перескакивая скрытый шаг")
    func nextSkipsHiddenStep() {
        #expect(WizardFlow.next(after: .permissions, in: all) == .model)
        #expect(WizardFlow.next(after: .permissions, in: noModel) == .hotkeys,
                "при скрытом шаге модели следующий — хоткеи")
    }

    @Test("С последнего шага вперёд некуда, с первого — назад некуда")
    func boundaries() {
        #expect(WizardFlow.next(after: .more, in: all) == nil)
        #expect(WizardFlow.previous(before: .hello, in: all) == nil)
        #expect(WizardFlow.previous(before: .hotkeys, in: noModel) == .permissions)
    }

    @Test("Шаг, которого нет в наборе, не ломает навигацию")
    func unknownStepIsSafe() {
        #expect(WizardFlow.next(after: .model, in: noModel) == nil)
        #expect(WizardFlow.previous(before: .model, in: noModel) == nil)
    }

    // MARK: - Progress indicator

    @Test("Индикатор считает по ТЕКУЩЕМУ набору — иначе обещает несуществующий экран")
    func positionUsesCurrentSteps() {
        let withModel = WizardFlow.position(of: .hotkeys, in: all)
        #expect(withModel == (index: 4, total: 6))
        let without = WizardFlow.position(of: .hotkeys, in: noModel)
        #expect(without == (index: 3, total: 5), "при скрытом шаге «4 из 5» обещало бы пятый экран")
    }

    @Test("Первый и последний шаг нумеруются корректно")
    func positionBoundaries() {
        #expect(WizardFlow.position(of: .hello, in: noModel).index == 1)
        #expect(WizardFlow.position(of: .more, in: noModel) == (index: 5, total: 5))
    }
}
