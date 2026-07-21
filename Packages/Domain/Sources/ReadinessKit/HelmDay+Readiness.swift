import Core
import Foundation

extension HelmDay {
  func adding(days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> HelmDay {
    let components = dateComponents()
    guard let date = calendar.date(from: components),
          let shifted = calendar.date(byAdding: .day, value: days, to: date)
    else {
      preconditionFailure("calendar could not shift HelmDay")
    }
    let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shifted)
    guard let helmDay = HelmDay(components: shiftedComponents) else {
      preconditionFailure("calendar produced incomplete day components")
    }
    return helmDay
  }
}
