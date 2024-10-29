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
import org.elasticsearch.compute.ann.Aggregator;
import org.elasticsearch.compute.ann.GroupingAggregator;
import org.elasticsearch.compute.ann.IntermediateState;
import org.elasticsearch.compute.data.Block;
import org.elasticsearch.compute.data.BooleanBlock;
import org.elasticsearch.compute.data.BooleanVector;
import org.elasticsearch.compute.data.CompositeBlock;
import org.elasticsearch.compute.data.LongBlock;
import org.elasticsearch.compute.data.Page;
import org.elasticsearch.compute.operator.DriverContext;
import org.elasticsearch.core.Releasable;

import java.util.List;

@Aggregator(
    value = {
        @IntermediateState(name = "sum", type = "LONG"),
        @IntermediateState(name = "seenAndFailed", type = "COMPOSITE_BLOCK"), }
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

        try (
            BooleanBlock failedBlock = page.getBlock(failedStateChannel);
            BooleanVector failedVector = failedBlock.asVector()
        ) {
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

    public static LongFallibleState init() {
        return new LongFallibleState(0);
    }

    public static LongFallibleArrayState initGrouping(BigArrays bigArrays) {
        return new LongFallibleArrayState(bigArrays, 0);
    }

    public static void combine(LongFallibleState state, long v) {
        state.longValue(combineValues(state.longValue(), v));
        state.seen(true);
    }

    public static void combine(LongFallibleArrayState state, int groupId, long v) {
        state.set(groupId, combineValues(state.getOrDefault(groupId), v));
    }

    public static void combineIntermediate(LongFallibleState state, long sum, Block seenAndFailed) {
        if (failed(seenAndFailed, 0)) {
            state.failed(true);
        } else if (seen(seenAndFailed, 0)) {
            combine(state, sum);
        }
    }

    public static void combineIntermediate(LongFallibleArrayState state, int groupId, long sum, Block seenAndFailed, int position) {
        // TODO: What to do with "position" here?
        if (failed(seenAndFailed, groupId)) {
            state.setFailed(groupId);
        } else if (seen(seenAndFailed, groupId)) {
            combine(state, groupId, sum);
        }
    }

    public static void combineStates(LongFallibleArrayState state, int groupId, LongFallibleArrayState inState, int inGroupId) {
        if (inState.hasFailed(inGroupId)) {
            state.setFailed(groupId);
        } else if (inState.hasValue(inGroupId)) {
            // TODO: Catch exception here
            state.set(groupId, combineValues(state.getOrDefault(groupId), inState.get(inGroupId)));
        }
    }

    private static long combineValues(long current, long v) {
        return Math.addExact(current, v);
    }

    private static boolean seen(Block seenAndFailed, int position) {
        // TODO: Implement logic to use either one or the other block
        return true; // seenAndFailed.getBlock(0).getBoolean(position) && !seenAndFailed.getBlock(1).getBoolean(position);
    }

    private static boolean failed(Block seenAndFailed, int position) {
        // TODO: Implement logic to use either one or the other block
        return true; // seenAndFailed.getBlock(0).getBoolean(position) && !seenAndFailed.getBlock(1).getBoolean(position);
    }

    /*public static class SingleState extends Releasable {

    }*/
}
