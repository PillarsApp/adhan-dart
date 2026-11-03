DateTime present(DateTime utc, Duration? utcOffset) =>
    utcOffset == null ? utc.toLocal() : utc.add(utcOffset);
