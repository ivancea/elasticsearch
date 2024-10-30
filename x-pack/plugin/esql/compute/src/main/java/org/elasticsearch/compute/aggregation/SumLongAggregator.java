/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.aggregation;

import org.elasticsearch.TransportVersion;
import org.elasticsearch.TransportVersions;
import org.elasticsearch.common.util.BigArrays;
import org.elasticsearch.common.util.LongArray;
import org.elasticsearch.compute.ann.Aggregator;
import org.elasticsearch.compute.ann.GroupingAggregator;
import org.elasticsearch.compute.ann.IntermediateState;
import org.elasticsearch.compute.data.Block;
import org.elasticsearch.compute.data.BooleanBlock;
import org.elasticsearch.compute.data.BooleanVector;
import org.elasticsearch.compute.data.CompositeBlock;
import org.elasticsearch.compute.data.IntVector;
import org.elasticsearch.compute.data.LongBlock;
import org.elasticsearch.compute.data.Page;
import org.elasticsearch.compute.operator.DriverContext;
import org.elasticsearch.core.Releasables;

import java.util.List;

@Aggregator(
    value = { @IntermediateState(name = "sum", type = "LONG"), @IntermediateState(name = "seenAndFailed", type = "COMPOSITE_BLOCK"), }
)
@GroupingAggregator
class SumLongAggregator {

    public static Page translateFrom(DriverContext driverContext, List<Integer> channels, Page page, TransportVersion version) {
        if (version.onOrAfter(TransportVersions.ESQL_SUM_LONG_AGG_OVERFLOW)) {
            return page;
        }

        int failedStateChannel = channels.get(2);

        // Old intermediate state didn't have the failed flag, so we add it to "false" here
        Block[] blocks = new Block[page.getBlockCount() + 1];
        // Original: [x A A y]
        // [_ _ _ _ _] -> [x A A _ _]
        for (int i = 0; i < failedStateChannel; i++) {
            blocks[i] = page.getBlock(i);
        }
        // [x A A _ _] -> [x A A _ y]
        for (int i = failedStateChannel; i < page.getBlockCount(); i++) {
            blocks[i + 1] = page.getBlock(i);
        }
        // [x A A _ y] -> [x A A N y]
        blocks[failedStateChannel] = driverContext.blockFactory().newConstantBooleanBlockWith(false, page.getPositionCount());

        return new Page(page.getPositionCount(), blocks);
    }

    public static Page translateTo(DriverContext driverContext, List<Integer> channels, Page page, TransportVersion version) {
        if (version.onOrAfter(TransportVersions.ESQL_SUM_LONG_AGG_OVERFLOW)) {
            return page;
        }

        int failedStateChannel = channels.get(2);

        try (BooleanBlock failedBlock = page.getBlock(failedStateChannel); BooleanVector failedVector = failedBlock.asVector()) {
            if (failedVector.allFalse() == false) {
                // If something failed, the other node won't be able to handle it, so we throw instead
                throw new ArithmeticException("long overflow");
            }

            // Old intermediate state didn't have the failed flag, so we remove it here so that it doesn't get sent to the old node
            Block[] blocks = new Block[page.getBlockCount() - 1];
            // Original: [x A A N y]
            // [_ _ _ _] -> [x A A _]
            for (int i = 0; i < failedStateChannel; i++) {
                blocks[i] = page.getBlock(i);
            }
            // [x A A _] -> [x A A y]
            for (int i = failedStateChannel + 1; i < page.getBlockCount(); i++) {
                blocks[i - 1] = page.getBlock(i);
            }

            return new Page(page.getPositionCount(), blocks);
        }
    }

    public static SingleState init() {
        return new SingleState(0);
    }

    public static GroupingState initGrouping(BigArrays bigArrays) {
        return new GroupingState(bigArrays, 0);
    }

    public static void combine(SingleState state, long v) {
        try {
            state.longValue(combineValues(state.longValue(), v));
            state.seen(true);
        } catch (ArithmeticException e) {
            state.failed(true);
        }
    }

    public static void combine(GroupingState state, int groupId, long v) {
        try {
            state.set(groupId, combineValues(state.getOrDefault(groupId), v));
        } catch (ArithmeticException e) {
            state.setFailed(groupId);
        }
    }

    public static void combineIntermediate(SingleState state, long sum, Block seenAndFailed) {
        if (failed(seenAndFailed, 0)) {
            state.failed(true);
        } else if (seen(seenAndFailed, 0)) {
            combine(state, sum);
        }
    }

    public static void combineIntermediate(GroupingState state, int groupId, long sum, Block seenAndFailed, int position) {
        // TODO: What to do with "position" here?
        if (failed(seenAndFailed, groupId)) {
            state.setFailed(groupId);
        } else if (seen(seenAndFailed, groupId)) {
            combine(state, groupId, sum);
        }
    }

    public static void combineStates(GroupingState state, int groupId, GroupingState inState, int inGroupId) {
        if (inState.hasFailed(inGroupId)) {
            state.setFailed(groupId);
        } else if (inState.hasValue(inGroupId)) {
            combine(state, groupId, inState.get(inGroupId));
        }
    }

    public static Block evaluateFinal(SingleState state, DriverContext driverContext) {
        if (state.seen() == false || state.failed()) {
            return driverContext.blockFactory().newConstantNullBlock(1);
        }
        return driverContext.blockFactory().newConstantLongBlockWith(state.longValue(), 1);
    }

    public static Block evaluateFinal(GroupingState state, IntVector selected, DriverContext driverContext) {
        return state.toValuesBlock(selected, driverContext);
    }

    private static long combineValues(long current, long v) {
        return Math.addExact(current, v);
    }

    private static boolean seen(Block seenAndFailed, int position) {
        if (seenAndFailed instanceof CompositeBlock composite) {
            return ((BooleanBlock) composite.getBlock(0)).getBoolean(position);
        }
        // In the old version, this block is just the "seen" block
        return ((BooleanBlock) seenAndFailed).getBoolean(position);
    }

    private static boolean failed(Block seenAndFailed, int position) {
        if (seenAndFailed instanceof CompositeBlock composite) {
            return ((BooleanBlock) composite.getBlock(1)).getBoolean(position);
        }
        // In the old version, this block doesn't exist, as failure aborts the query
        return false;
    }

    /**
     * Copy of {@link LongFallibleState} with a changed toIntermediate method.
     */
    static class SingleState implements AggregatorState {
        private long value;
        private boolean seen;
        private boolean failed;

        SingleState(long init) {
            this.value = init;
        }

        long longValue() {
            return value;
        }

        void longValue(long value) {
            this.value = value;
        }

        boolean seen() {
            return seen;
        }

        void seen(boolean seen) {
            this.seen = seen;
        }

        boolean failed() {
            return failed;
        }

        void failed(boolean failed) {
            this.failed = failed;
        }

        /** Extracts an intermediate view of the contents of this state.  */
        @Override
        public void toIntermediate(Block[] blocks, int offset, DriverContext driverContext) {
            assert blocks.length >= offset + 2;
            blocks[offset + 0] = driverContext.blockFactory().newConstantLongBlockWith(value, 1);
            blocks[offset + 1] = new CompositeBlock(
                new Block[] {
                    driverContext.blockFactory().newConstantBooleanBlockWith(seen, 1),
                    driverContext.blockFactory().newConstantBooleanBlockWith(failed, 1) }
            );
        }

        @Override
        public void close() {}
    }

    /**
     * Copy of {@link LongFallibleArrayState} with a changed toIntermediate method.
     */
    static class GroupingState extends AbstractFallibleArrayState implements GroupingAggregatorState {
        private final long init;

        private LongArray values;

        GroupingState(BigArrays bigArrays, long init) {
            super(bigArrays);
            this.values = bigArrays.newLongArray(1, false);
            this.values.set(0, init);
            this.init = init;
        }

        long get(int groupId) {
            return values.get(groupId);
        }

        long getOrDefault(int groupId) {
            return groupId < values.size() ? values.get(groupId) : init;
        }

        void set(int groupId, long value) {
            ensureCapacity(groupId);
            values.set(groupId, value);
            trackGroupId(groupId);
        }

        void increment(int groupId, long value) {
            ensureCapacity(groupId);
            values.increment(groupId, value);
            trackGroupId(groupId);
        }

        Block toValuesBlock(org.elasticsearch.compute.data.IntVector selected, DriverContext driverContext) {
            if (false == trackingGroupIds() && false == anyFailure()) {
                try (var builder = driverContext.blockFactory().newLongVectorFixedBuilder(selected.getPositionCount())) {
                    for (int i = 0; i < selected.getPositionCount(); i++) {
                        builder.appendLong(i, values.get(selected.getInt(i)));
                    }
                    return builder.build().asBlock();
                }
            }
            try (LongBlock.Builder builder = driverContext.blockFactory().newLongBlockBuilder(selected.getPositionCount())) {
                for (int i = 0; i < selected.getPositionCount(); i++) {
                    int group = selected.getInt(i);
                    if (hasValue(group) && !hasFailed(group)) {
                        builder.appendLong(values.get(group));
                    } else {
                        builder.appendNull();
                    }
                }
                return builder.build();
            }
        }

        private void ensureCapacity(int groupId) {
            if (groupId >= values.size()) {
                long prevSize = values.size();
                values = bigArrays.grow(values, groupId + 1);
                values.fill(prevSize, values.size(), init);
            }
        }

        /** Extracts an intermediate view of the contents of this state.  */
        @Override
        public void toIntermediate(
            Block[] blocks,
            int offset,
            IntVector selected,
            org.elasticsearch.compute.operator.DriverContext driverContext
        ) {
            assert blocks.length >= offset + 2;
            try (
                var valuesBuilder = driverContext.blockFactory().newLongBlockBuilder(selected.getPositionCount());
                var hasValueBuilder = driverContext.blockFactory().newBooleanVectorFixedBuilder(selected.getPositionCount());
                var hasFailedBuilder = driverContext.blockFactory().newBooleanVectorFixedBuilder(selected.getPositionCount())
            ) {
                for (int i = 0; i < selected.getPositionCount(); i++) {
                    int group = selected.getInt(i);
                    if (group < values.size()) {
                        valuesBuilder.appendLong(values.get(group));
                    } else {
                        valuesBuilder.appendLong(0); // TODO can we just use null?
                    }
                    hasValueBuilder.appendBoolean(i, hasValue(group));
                    hasFailedBuilder.appendBoolean(i, hasFailed(group));
                }
                blocks[offset + 0] = valuesBuilder.build();
                blocks[offset + 1] = new CompositeBlock(
                    new Block[] { hasValueBuilder.build().asBlock(), hasFailedBuilder.build().asBlock() }
                );
            }
        }

        @Override
        public void close() {
            Releasables.close(values, super::close);
        }
    }
}
