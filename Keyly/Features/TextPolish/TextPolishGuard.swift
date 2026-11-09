import Foundation

/// Guard on the processing result: checks that the model RETURNED the user's text rather than
/// answering it. A PURE type with no store, network or UI — judges two strings, returns a verdict.
///
/// WHY IT EXISTS. A recurring real-world problem: instead of transcribing what the user says
/// verbatim, the model answered their speech, while the user wanted the text of their question
/// back. This was fixed once already with a ban in the TRANSCRIPTION prompt
/// (`TranscriptionPrompt`, commit 7b6ff04). It didn't hold, because the text goes to a chat
/// model a SECOND time, at the processing step (`TextPolisher`), where there was no ban at all.
///
/// WHY NOT A THIRD PROMPT APPENDIX. An appendix relies on the model's obedience: it can only be
/// verified with a real paid call, and it may fail on any next phrase. The guard looks at the
/// RESULT and so works regardless of whether the model obeyed. That's the difference between
/// "we asked it not to" and "it physically can't reach the field".
///
/// WHAT THE CALLER DOES on rejection: returns the ORIGINAL. Same principle as `TextPolisher` on a
/// network error — losing the processing is better than losing the dictation.
///
/// WHY THESE SIGNALS. Each follows from what the prompt ALLOWS and FORBIDS, not tuned to
/// examples — otherwise it would fall apart on the first phrase outside the set:
///  · `added` — NO level is allowed to add text (adding intros, conclusions, headings and
///    comments is forbidden in both `tidy` and `rewrite`). An answering model always adds —
///    that's its nature.
///  · `removed` — `tidy` explicitly forbids deleting words, `rewrite` ALLOWS removing fillers.
///    So for `.reworded` fillers aren't counted.
///  · `alien replacements` — a replacement is legitimate when the word is RECOGNIZABLE in the
///    source: spelling (a colloquial short form → the full word), a brand heard by ear (Cyrillic
///    "githab" → GitHub), wrong layout (ghbdtn → the Russian for "hello"). All of these give
///    similar strings once mapped to one alphabet. Replacing one unrelated word with another
///    isn't recognizable.
///  · `appended` — a crude length signal, judged ONLY together with an absolute increase: on
///    short input the ratio lies (a two-letter word → the same word capitalized with a period
///    is already 1.33×).
enum TextPolishGuard {

    /// How much the result is ALLOWED to differ from the input. Set by the level's promise, not
    /// picked by eye.
    enum Strictness: Equatable {
        /// "Tidy up": the words stay the same. Spelling, brands, punctuation, paragraphs are fixed.
        case verbatimWords
        /// "Tidy up and rewrite": wording MAY change, fillers are removed. Removal is judged
        /// with a looser threshold here.
        case reworded
        /// Typo fixing: words change LEGITIMATELY and in bulk — the input is wrong by definition and
        /// the output is right. All word signals apply, but replacements here are almost always
        /// RECOGNIZABLE (spelling, layout), so what cuts is added and removed words, not the
        /// share of replacements.
        case spellingOnly
    }

    /// Why the result was rejected. The reason must be DISTINCT: the user must see "the model
    /// answered instead of editing", not a generic "processing failed" — otherwise they can't tell
    /// a substitution from a network failure and will hit the same problem again.
    enum Reason: String, Equatable {
        case added      = "добавила своё"
        case replaced   = "подменила слова"
        case removed    = "выкинула сказанное"
        case appended   = "дописала ответ"

        var explanation: String { rawValue }
    }

    enum Verdict: Equatable {
        case passed
        case rejected(Reason)
    }

    // MARK: - Thresholds

    // Calibrated on 30 "input → output" pairs (14 honest, 16 failures), 0 errors.
    // The pairs are synthetic — built from the prompts and known failure cases; real dictation
    // refines them but doesn't cancel the reasoning behind each signal.

    /// Share of INSERTED words in the result. Honest processing adds no words at all; 0.15 is
    /// headroom for function words that punctuation drags along.
    private static let maxAdded = 0.15
    /// Absolute floor for the previous threshold — same reason as for replacements: on short
    /// output the share lies. Restructuring a loose spoken sentence into a written one can give
    /// two insertions in eight words, i.e. 25%, even though the prompt EXPLICITLY asks to
    /// "restructure loose spoken constructions".
    private static let minAddedWords = 3
    /// For "rewrite" the floor is higher: REORDERING words is allowed there, and for the alignment
    /// a move is a deletion plus an insertion, so an honest edit incriminates itself. "We discussed
    /// this with the team yesterday for a long time" → "Yesterday we discussed this with the team
    /// for a long time" gives insertions without a single new word.
    private static let minAddedWordsWhenReworded = 5
    /// Share of replacements with a word NOT recognizable in the source. In an honest edit brands
    /// and spelling are recognizable; 0.35 is headroom for phonetic replacements where letters
    /// diverge (Cyrillic "aifon" → iPhone).
    private static let maxAlienReplacements = 0.35
    /// Absolute floor for the previous threshold. Without it short speech with numbers gets
    /// rejected systematically: "call on the twenty-ninth at three" → "Call on the 29th at three"
    /// is two replacements in a five-word output, i.e. 0.4, though the prompt REQUIRES both. A
    /// spelled-out number and digits look alike in no alphabet, so there's no way to recognize
    /// one in the other — the defense is not tuning the share but requiring the substitution to
    /// be MASSIVE. Two replacements are never a change of meaning; eight can be.
    private static let minAlienWords = 3
    /// Share of input words dropped. Fillers don't count where removing them is allowed.
    private static let maxRemoved = 0.25
    /// Same for "Tidy up and rewrite". The threshold is looser, but it EXISTS: this level's prompt
    /// allows removing fillers and repetitions but explicitly forbids "removing substantive
    /// statements, even if they seem unnecessary".
    ///
    /// Nothing was judged here before, and that was a hole: for a dictated "make a summary"
    /// request the model returned five words instead of twenty-three — no added words, no alien
    /// replacements, negative growth — and passed as honest work. The user lost what they said,
    /// which is exactly the problem: the model must not follow instructions found in the
    /// dictated text.
    private static let maxRemovedWhenReworded = 0.45
    /// Appended answer: both conditions at once. The absolute threshold protects short input from
    /// false positives.
    private static let maxGrowthChars = 80
    private static let maxGrowthRatio = 1.6

    /// How many consecutive words honest processing may insert. Punctuation and capitals add no
    /// words; a paragraph is a line break, not a word. A contiguous block this long means the
    /// model started speaking in its own voice.
    private static let maxInsertedRun = 8

    /// Beyond this many words the alignment isn't built: it's quadratic, and 1500 words is ~10
    /// minutes of continuous speech. The appended-answer signal still uses the FULL length.
    private static let alignmentWordLimit = 1500

    // MARK: - Entry

    /// Strictness for a processing level. `nil` — the level doesn't call the model, nothing to judge.
    static func strictness(for level: TextPolishLevel) -> Strictness? {
        switch level {
        case .verbatim: return nil
        case .tidy:     return .verbatimWords
        case .rewrite:  return .reworded
        }
    }

    /// Main entry. `input` is what the user said or wrote; `output` is what the model returned.
    static func judge(input: String, output: String, strictness: Strictness) -> Verdict {
        let source = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Text untouched — the most common honest outcome ("if the text is already correct,
        // return it unchanged"). Nothing to count.
        guard source != result else { return .passed }
        guard !source.isEmpty, !result.isEmpty else { return .passed }

        // The appended signal uses the FULL length, before any alignment: it catches the case
        // where the beginning was processed honestly and an answer was glued to the end.
        let addedChars = result.count - source.count
        let growth = Double(result.count) / Double(max(1, source.count))
        if addedChars > maxGrowthChars && growth > maxGrowthRatio {
            return .rejected(.appended)
        }

        var before = words(source)
        var after  = words(result)
        guard !before.isEmpty, !after.isEmpty else { return .passed }

        // Very long speech: alignment is quadratic and would cost too much on the full text. We
        // judge the BEGINNING AND END — still judge, not skip.
        //
        // Measured: 450 words (3 minutes of speech) — 12 ms, 1500 words — 52 ms. Hence the limit.
        // There used to be `return .passed` here, and that was a hole: for dictation longer than
        // the limit, the model's answer reached the field intact. The beginning alone isn't enough
        // either — a test showed it: an appended answer sits at the END, and a window of the
        // first words never sees it.
        before = window(before)
        after  = window(after)

        let tally = align(before, after, strictness: strictness)
        let outCount = Double(after.count)
        let inCount  = Double(before.count)

        // A contiguous inserted block is an ABSOLUTE sign and outranks the share. In long speech an
        // appended answer drowns in the ratio (22 words out of 1500 is one and a half percent),
        // but "12 words inserted in a row" never happens in an honest edit: it inserts single
        // words in different places, if at all.
        if tally.longestInsertedRun >= maxInsertedRun { return .rejected(.added) }
        let addedFloor = strictness == .reworded ? minAddedWordsWhenReworded : minAddedWords
        if tally.inserted >= addedFloor,
           Double(tally.inserted) / outCount > maxAdded { return .rejected(.added) }
        if tally.alien >= minAlienWords,
           Double(tally.alien) / outCount > maxAlienReplacements { return .rejected(.replaced) }
        let removedLimit = strictness == .reworded ? maxRemovedWhenReworded : maxRemoved
        if Double(tally.deleted) / inCount > removedLimit { return .rejected(.removed) }
        return .passed
    }

    // MARK: - Alignment

    private struct Tally {
        var inserted = 0    // words that appeared from nowhere
        var deleted  = 0    // input words that vanished
        var alien    = 0    // replacements with an unrecognizable word
        var longestInsertedRun = 0  // longest CONTIGUOUS block of inserted words
    }

    /// Splits the pair into insertions, deletions and replacements. A replacement is a deletion
    /// and an insertion at the same place — the way a person reading "before → after" sees it too.
    private static func align(_ before: [String], _ after: [String], strictness: Strictness) -> Tally {
        var tally = Tally()
        for block in blocks(before, after) {
            let removed = Array(before[block.sourceRange])
            let added   = Array(after[block.resultRange])
            switch (removed.isEmpty, added.isEmpty) {
            case (true, true):
                continue
            case (true, false):
                tally.inserted += added.count
                tally.longestInsertedRun = max(tally.longestInsertedRun, added.count)
            case (false, true):
                tally.deleted += removed.filter { !(strictness == .reworded && isFiller($0)) }.count
            case (false, false):
                // Replacement block: pair up in order, count the remainder as pure insertion or
                // deletion.
                let paired = min(removed.count, added.count)
                for index in 0..<paired where !isRecognizable(removed[index], added[index]) {
                    tally.alien += 1
                }
                if added.count > paired {
                    let extra = added.count - paired
                    tally.inserted += extra
                    tally.longestInsertedRun = max(tally.longestInsertedRun, extra)
                }
                if removed.count > paired {
                    tally.deleted += removed[paired...]
                        .filter { !(strictness == .reworded && isFiller($0)) }.count
                }
            }
        }
        return tally
    }

    /// Alignment window: either the whole text or its beginning and end. The middle of long speech
    /// is skipped on purpose — a substitution diverges from the first words, and an appended answer
    /// sticks to the end.
    ///
    /// KNOWN LIMITATION. On text where the same words repeat in a strict cycle, alignment
    /// degenerates: an insertion gets matched against earlier occurrences and smeared into small
    /// pieces, so the contiguous block is no longer visible. Real speech isn't like that (checked:
    /// with a 40-word vocabulary an appended answer is caught, with a 14-word cycle it isn't), so
    /// no workaround was built for an impossible input. If such text does arrive, the other
    /// signals still apply, and the worst outcome is "processing passed", not "text lost".
    private static func window(_ words: [String]) -> [String] {
        guard words.count > alignmentWordLimit else { return words }
        let half = alignmentWordLimit / 2
        return Array(words.prefix(half)) + Array(words.suffix(half))
    }

    private struct Block {
        let sourceRange: Range<Int>
        let resultRange: Range<Int>
    }

    /// Difference blocks between two word sequences, based on the longest common subsequence.
    /// Matching stretches are skipped, the rest is returned as "before → after".
    private static func blocks(_ before: [String], _ after: [String]) -> [Block] {
        let n = before.count, m = after.count
        // lcs[i][j] — LCS length of the suffixes before[i...] and after[j...]
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = before[i] == after[j]
                        ? lcs[i + 1][j + 1] + 1
                        : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }

        var result: [Block] = []
        var i = 0, j = 0
        var pendingSource = 0, pendingResult = 0
        func flush() {
            if pendingSource < i || pendingResult < j {
                result.append(Block(sourceRange: pendingSource..<i, resultRange: pendingResult..<j))
            }
            pendingSource = i; pendingResult = j
        }

        while i < n && j < m {
            if before[i] == after[j] {
                flush()
                i += 1; j += 1
                pendingSource = i; pendingResult = j
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        i = n; j = m
        flush()
        return result
    }

    // MARK: - Words

    /// Normalized words: case and punctuation don't matter, editing them is allowed.
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ")
            .map(String.init)
    }

    /// Filler words the `rewrite` level IS ALLOWED to remove — the prompt lists them itself.
    /// The list is kept short on purpose: it excuses deletions, so it weakens the guard.
    private static let fillers: Set<String> = [
        "э", "ээ", "эээ", "ну", "вот", "типа", "значит", "короче", "блин", "как", "бы", "это",
        "самое", "там", "же", "уж", "так", "сказать"
    ]

    private static func isFiller(_ word: String) -> Bool { fillers.contains(word) }

    /// Whether "after" is recognizable in "before". Legitimate replacements — spelling, a brand
    /// heard by ear, wrong layout — give similar strings when compared in one alphabet. A change
    /// of meaning doesn't.
    private static func isRecognizable(_ source: String, _ result: String) -> Bool {
        let candidates = [
            (source, result),
            (transliterate(source), result),
            (source, transliterate(result)),
            (transliterate(source), transliterate(result)),
            (fromLatinLayout(source), result),
            (source, fromLatinLayout(result))
        ]
        return candidates.contains { similarity($0.0, $0.1) >= 0.55 }
    }

    private static let cyrillicToLatin: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ж": "zh", "з": "z", "и": "i",
        "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s",
        "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"
    ]

    /// A brand heard by ear arrives in Cyrillic and gets fixed to Latin: Cyrillic "githab" →
    /// GitHub. The prompt REQUIRES this replacement, so it must not be penalized.
    private static func transliterate(_ word: String) -> String {
        word.reduce(into: "") { $0 += cyrillicToLatin[$1] ?? String($1) }
    }

    private static let latinLayout: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ",
        "p": "з", "[": "х", "]": "ъ", "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р",
        "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э", "z": "я", "x": "ч", "c": "с", "v": "м",
        "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю"
    ]

    /// Text typed in the wrong layout is a legitimate fix where not a single letter matches:
    /// "ghbdtn" → the Russian word for "hello".
    private static func fromLatinLayout(_ word: String) -> String {
        word.reduce(into: "") { $0.append(latinLayout[$1] ?? $1) }
    }

    /// Similarity of two strings: 2×(LCS length) / (sum of lengths).
    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty ? 1 : 0 }
        var row = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            var previousDiagonal = 0
            for j in 1...b.count {
                let current = row[j]
                row[j] = a[i - 1] == b[j - 1] ? previousDiagonal + 1 : max(row[j], row[j - 1])
                previousDiagonal = current
            }
        }
        return 2.0 * Double(row[b.count]) / Double(a.count + b.count)
    }
}
