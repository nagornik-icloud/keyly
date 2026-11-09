import Testing
@testable import KeylyLogic

/// The choice offered when the model is missing.
struct ModelMissingChoiceTests {

    @Test("Модель на месте — вопроса нет")
    func readyNeedsNoQuestion() {
        #expect(ModelMissingChoice.action(modelReady: true, hasKey: true, stored: nil) == .useLocal)
        #expect(ModelMissingChoice.action(modelReady: true, hasKey: false, stored: .useCloud) == .useLocal)
    }

    @Test("Нет модели и нет ключа — отказ, спрашивать не о чем")
    func noKeyNoQuestion() {
        // Cloud without a key is no way out; asking "download or use the cloud" would be a mockery.
        #expect(ModelMissingChoice.action(modelReady: false, hasKey: false, stored: nil) == .refuse)
    }

    @Test("Нет модели, есть ключ, ответа ещё не было — спрашиваем ОДИН раз")
    func asksOnce() {
        #expect(ModelMissingChoice.action(modelReady: false, hasKey: true, stored: nil) == .ask)
    }

    @Test("Разрешил облако — уходим молча, второй раз не спрашиваем")
    func cloudRemembered() {
        #expect(ModelMissingChoice.action(modelReady: false, hasKey: true, stored: .useCloud) == .cloud)
    }

    @Test("Выбрал качать — в облако НЕ уводим даже при живом ключе")
    func downloadMeansNoCloud() {
        // Otherwise choosing "download" would mean nothing: the data route would change against the answer.
        #expect(ModelMissingChoice.action(modelReady: false, hasKey: true, stored: .download) == .refuse)
    }
}
