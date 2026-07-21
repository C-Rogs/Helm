import OSLog

public func helmLogger(category: HelmCategory) -> Logger {
    Logger(subsystem: HelmSubsystem.value, category: category.rawValue)
}
