import Testing
@testable import KeylyLogic

/// Found in a real run: "…or not.This is a penalty": the insertion got glued to the text.
@Suite struct InsertSpacingTests {

    @Test func послеБуквыИТочкиПробелНужен() {
        #expect(InsertSpacing.needsLeadingSpace(previous: "т", inserted: "Это"))
        #expect(InsertSpacing.needsLeadingSpace(previous: ".", inserted: "Это"))
    }

    @Test func послеПробелаИПереносаНеНужен() {
        #expect(!InsertSpacing.needsLeadingSpace(previous: " ", inserted: "Это"))
        #expect(!InsertSpacing.needsLeadingSpace(previous: "\n", inserted: "Это"))
    }

    @Test func вПустомПолеНеНужен() {
        #expect(!InsertSpacing.needsLeadingSpace(previous: nil, inserted: "Это"))
    }

    /// After an opening bracket or quote a space would look like a typo.
    @Test func послеОткрывающихЗнаковНеНужен() {
        #expect(!InsertSpacing.needsLeadingSpace(previous: "(", inserted: "это"))
        #expect(!InsertSpacing.needsLeadingSpace(previous: "«", inserted: "это"))
    }

    /// An insertion that starts with punctuation does not want a space before it.
    @Test func передЗнакомПрепинанияНеНужен() {
        #expect(!InsertSpacing.needsLeadingSpace(previous: "т", inserted: ", а дальше"))
    }

    @Test func готовыйТекстСобираетсяПравильно() {
        #expect(InsertSpacing.prepared("Это", previous: ".") == " Это")
        #expect(InsertSpacing.prepared("Это", previous: " ") == "Это")
    }
}
