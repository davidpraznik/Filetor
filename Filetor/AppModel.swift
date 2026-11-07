import SwiftUI
import Observation

@Observable
final class AppModel {
    let panes = [PaneModel(), PaneModel()]
    var activeIndex = 0
    var dual = true

    var active: PaneModel { panes[activeIndex] }
}
