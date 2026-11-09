#if DEBUG
import SwiftUI

/// How to fill the hotkey bar — a design choice. Not wired into the product.
///
/// The issue behind it was raised twice, independently. Measured: the bar's content
/// (label + field + "…") takes 20–27% of its width; up to 582pt is bare fill. Worse, the bar
/// fill `#141414` MATCHES the fill of the SELECTED option on the same screen ("Also polish
/// the style"); only the hairline brightness differs — `#1e1e1e` vs `#292929`. The eye reads
/// the settings bar as "something is selected here".
///
/// Four answers to "what to do with this emptiness", each in the three states where they
/// diverge: assigned · unassigned · taken.
///
/// HONEST FRAME. Width is locked to 738pt — the content column width in the product. Earlier
/// mockups were drawn at full window width (959pt) and overstated the share taken by the
/// content, i.e. misrepresented exactly the value in dispute.
struct HotkeyBarFill: View {
    let page: Int

    private let contentWidth: CGFloat = 738

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                if page == 1 {
                    variant("1 · как сейчас",
                            "Полоса во всю ширину, справа ничего. Показан для сравнения — это то, на что пожаловались обе линзы.",
                            cost: "80% площади не держит ничего; та же грамматика, что у выбранной карточки ниже на экране.") {
                        bar { row(actions: .dots) }
                    }
                    variant("2 · полоса по содержимому",
                            "Плашка обтягивает подпись, поле и «…». Правее — чистый фон карточки, как у любого другого блока.",
                            cost: "Полоса перестаёт быть строкой во всю ширину — а именно её ширину просили в прошлый раз («растяни блок»).") {
                        bar(hugs: true) { row(actions: .dots) }
                    }
                } else {
                    variant("3 · действия словами у правого края",
                            "«…» исчезает, вместо него два подписанных действия, прибитых к правому краю. Пустота между полем и ними — воздух между началом и концом строки, а не дыра.",
                            cost: "Два слова вместо одного глифа — плотнее; «Снять» видно всегда, даже когда снимать не собираются.") {
                        bar { row(actions: .words) }
                    }
                    variant("4 · без плашки",
                            "Подпись и поле стоят в потоке, как «API КЛЮЧ» и «МОДЕЛЬ» рядом. Плашки нет вовсе — спорить с выбранной карточкой нечем.",
                            cost: "Хоткей перестаёт выделяться среди соседних настроек — он снова «просто ещё одно поле».") {
                        VStack(alignment: .leading, spacing: Theme.Space.s) {
                            Text("ХОТКЕЙ").font(Theme.Typography.mono(11, .semibold))
                                .tracking(1.0).foregroundStyle(Theme.Colors.fgDim)
                            HStack(spacing: 6) { field("F3"); dots }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Color.clear.frame(height: 8)
            }
            .padding(Theme.Space.xl)
        }
        .background(Theme.Colors.bg)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Чем заполнить полосу хоткея")
                .font(Theme.Typography.title(17)).foregroundStyle(Theme.Colors.fg)
            // The caption names EXACTLY what the frame shows. The first version also promised
            // "unassigned" and "taken" states that aren't here: the variants differ by the right edge
            // of the row, not by state, and extra rows would only bloat the frame. A caption promise
            // the frame doesn't back up is a lie of exactly the kind that has bitten before.
            Text("Ширина 738pt — как в продукте. Под каждой полосой стоит ВЫБРАННЫЙ вариант настройки: именно с ним она и спутывается.")
                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.fgMuted)
        }
    }

    @ViewBuilder
    private func variant<C: View>(_ title: String, _ note: String, cost: String,
                                  @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(title).font(Theme.Typography.mono(11, .semibold)).foregroundStyle(Theme.Colors.accent)
            Text(note).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.fgDim)
                .fixedSize(horizontal: false, vertical: true)
            // Each variant is shown INSIDE a card next to the selected strictness option — that is
            // what the bar gets confused with. A frame without the neighbour wouldn't show the problem.
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                content()
                selectedNeighbour
            }
            .padding(Theme.Space.l)
            .frame(width: contentWidth, alignment: .leading)
            .background(Theme.Colors.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("цена:").font(Theme.Typography.mono(9)).foregroundStyle(Theme.Colors.fgDim)
                Text(cost).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: contentWidth, alignment: .leading)
        }
    }

    /// The very neighbour the bar gets confused with: the SELECTED settings option.
    private var selectedNeighbour: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "largecircle.fill.circle")
                    .font(.system(size: 13)).foregroundStyle(Theme.Colors.fg)
                Text("Ещё и причесать стиль").font(Theme.Typography.body).foregroundStyle(Theme.Colors.fg)
            }
            Text("Плюс абзацы и лёгкая правка формулировок. Текст может измениться.")
                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.fgMuted)
                .padding(.leading, 21)
        }
        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .fill(Theme.Colors.surfaceHover)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(Theme.Colors.borderStrong, lineWidth: 1)))
    }

    private enum Actions { case dots, words }

    @ViewBuilder
    private func bar<C: View>(hugs: Bool = false, @ViewBuilder content: () -> C) -> some View {
        content()
            .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
            .frame(maxWidth: hugs ? nil : .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Colors.surfaceHover)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .stroke(Theme.Colors.border, lineWidth: 1)))
            .fixedSize(horizontal: hugs, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(actions: Actions) -> some View {
        HStack(spacing: Theme.Space.m) {
            Text("ХОТКЕЙ").font(Theme.Typography.mono(11, .semibold))
                .tracking(1.0).foregroundStyle(Theme.Colors.fgDim)
            field("F3")
            if actions == .dots { dots }
            Spacer(minLength: 0)
            if actions == .words {
                HStack(spacing: Theme.Space.m) {
                    Text("Изменить").font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.accent)
                    Text("Снять").font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.fgDim)
                }
            }
        }
    }

    private var dots: some View {
        Image(systemName: "ellipsis").font(.system(size: 12)).foregroundStyle(Theme.Colors.fgDim)
    }

    /// The field — same as in the product: inset, hugs the value, at least 64pt wide.
    private func field(_ value: String) -> some View {
        Text(value)
            .font(Theme.Typography.keys(13, .medium))
            .foregroundStyle(Theme.Colors.fg)
            .padding(.horizontal, Theme.Space.s)
            .frame(minWidth: 64, minHeight: Theme.Size.control, maxHeight: Theme.Size.control)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Theme.Colors.bg)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .stroke(Theme.Colors.borderStrong, lineWidth: 1)))
    }
}
#endif
