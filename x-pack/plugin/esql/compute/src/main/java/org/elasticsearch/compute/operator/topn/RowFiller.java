/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.elasticsearch.compute.operator.BreakingBytesRefBuilder;
import org.elasticsearch.core.Releasable;

interface RowFiller extends Releasable {
    void writeSortKey(int i, Row row);

    void writeValues(int i, Row row);

    /**
     * Returns the number of group IDs for position {@code i}.
     * For ungrouped top-N this is always 1. For grouped top-N with multivalue group keys,
     * this can be greater than 1 (one per combination of multivalue key values).
     */
    default int groupIdCount(int i) {
        return 1;
    }

    /**
     * Sets the group ID at index {@code groupIndex} for position {@code i} on the given row.
     * Only meaningful for grouped top-N; the default is a no-op.
     */
    default void setGroupId(int i, int groupIndex, Row row) {}

    @Override
    default void close() {}

    // When rows are very long, appending the values one by one can lead to lots of allocations.
    // To avoid this, pre-allocate at least as much size as in the last seen row.
    // Let the pre-allocation size decay in case we only have 1 huge row and smaller rows otherwise.
    static int newPreAllocSize(BreakingBytesRefBuilder builder, int spareValuesPreAllocSize) {
        return Math.max(builder.length(), spareValuesPreAllocSize / 2);
    }
}
