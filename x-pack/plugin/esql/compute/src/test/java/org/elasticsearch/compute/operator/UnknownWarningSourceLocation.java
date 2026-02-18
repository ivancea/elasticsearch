/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator;

/**
 * A {@link WarningSourceLocation} to use when the actual source is unknown in tests.
 * Uses the same sentinel values (-1, -2, null, "") as other "unknown source" usages in the codebase.
 */
public enum UnknownWarningSourceLocation implements WarningSourceLocation {
    INSTANCE;

    @Override
    public int lineNumber() {
        return -1;
    }

    @Override
    public int columnNumber() {
        return -2;
    }

    @Override
    public String viewName() {
        return null;
    }

    @Override
    public String text() {
        return "";
    }
}
