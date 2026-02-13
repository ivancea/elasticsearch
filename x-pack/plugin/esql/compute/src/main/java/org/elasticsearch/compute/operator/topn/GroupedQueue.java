/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.elasticsearch.common.breaker.CircuitBreaker;
import org.elasticsearch.common.util.BigArrays;
import org.elasticsearch.common.util.ObjectArray;
import org.elasticsearch.core.Releasables;

import java.util.ArrayList;
import java.util.List;

import static org.apache.lucene.util.RamUsageEstimator.shallowSizeOfInstance;

/**
 * A {@link TopNQueue} that maintains a separate {@link UngroupedQueue} per group, indexed by
 * integer group IDs assigned by a {@link org.elasticsearch.compute.aggregation.blockhash.BlockHash}.
 * Replaces the previous {@code HashMap<BytesRef, UngroupedQueue>} approach with a
 * {@link BigArrays}-backed {@link ObjectArray} for better performance and circuit breaker integration.
 */
class GroupedQueue implements TopNQueue {
    private static final long SHALLOW_SIZE = shallowSizeOfInstance(GroupedQueue.class);

    private final CircuitBreaker breaker;
    private final BigArrays bigArrays;
    private final int topCount;
    private ObjectArray<UngroupedQueue> queues;

    GroupedQueue(CircuitBreaker breaker, BigArrays bigArrays, int topCount) {
        this.breaker = breaker;
        this.bigArrays = bigArrays;
        this.topCount = topCount;
        this.queues = bigArrays.newObjectArray(0);
    }

    @Override
    public String toString() {
        return size() + "/" + queues.size() + "/" + topCount;
    }

    @Override
    public int size() {
        int totalSize = 0;
        for (long i = 0; i < queues.size(); i++) {
            UngroupedQueue queue = queues.get(i);
            if (queue != null) {
                totalSize += queue.size();
            }
        }
        return totalSize;
    }

    @Override
    public Row addRow(Row row) {
        var groupedRow = (GroupedRow) row;
        return getOrCreateQueue(groupedRow.groupId).addRow(groupedRow);
    }

    private UngroupedQueue getOrCreateQueue(int groupId) {
        if (groupId >= queues.size()) {
            queues = bigArrays.grow(queues, groupId + 1);
        }
        UngroupedQueue queue = queues.get(groupId);
        if (queue == null) {
            queue = UngroupedQueue.build(breaker, topCount);
            queues.set(groupId, queue);
        }
        return queue;
    }

    @Override
    public List<Row> popAll() {
        List<Row> allRows = new ArrayList<>(size());
        for (long i = 0; i < queues.size(); i++) {
            UngroupedQueue queue = queues.get(i);
            if (queue != null) {
                queue.popAllInto(allRows);
                queue.close();
                queues.set(i, null);
            }
        }
        // TODO this sorts all rows across all groups using the main sort key, ignoring the individual groups. We *might* want to sort only
        // within each group.
        allRows.sort((r1, r2) -> -r1.compareTo(r2));
        return allRows;
    }

    @Override
    public long ramBytesUsed() {
        long total = SHALLOW_SIZE;
        if (queues != null) {
            total += queues.ramBytesUsed();
            for (long i = 0; i < queues.size(); i++) {
                UngroupedQueue queue = queues.get(i);
                if (queue != null) {
                    total += queue.ramBytesUsed();
                }
            }
        }
        return total;
    }

    @Override
    public void close() {
        Releasables.close(() -> {
            if (queues != null) {
                for (long i = 0; i < queues.size(); i++) {
                    UngroupedQueue queue = queues.get(i);
                    if (queue != null) {
                        queue.close();
                        queues.set(i, null);
                    }
                }
            }
        }, queues);
    }
}
