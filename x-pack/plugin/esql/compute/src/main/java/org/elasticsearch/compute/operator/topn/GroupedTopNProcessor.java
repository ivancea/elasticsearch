/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.elasticsearch.common.breaker.CircuitBreaker;
import org.elasticsearch.compute.aggregation.GroupingAggregatorFunction;
import org.elasticsearch.compute.aggregation.blockhash.BlockHash;
import org.elasticsearch.compute.data.Block;
import org.elasticsearch.compute.data.BlockFactory;
import org.elasticsearch.compute.data.ElementType;
import org.elasticsearch.compute.data.IntArrayBlock;
import org.elasticsearch.compute.data.IntBigArrayBlock;
import org.elasticsearch.compute.data.IntBlock;
import org.elasticsearch.compute.data.IntVector;
import org.elasticsearch.compute.data.Page;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.IntStream;

/**
 * A {@link TopNProcessor} for grouped top-N operations. Uses a {@link BlockHash} to efficiently
 * map group key columns to integer group IDs, and routes rows to per-group priority queues.
 */
class GroupedTopNProcessor implements TopNProcessor {
    /**
     * Emit batch size for the BlockHash's {@link org.elasticsearch.compute.aggregation.blockhash.AddPage}.
     * Used as a tuning parameter; {@link #computeGroupIds} correctly merges multiple callbacks per
     * position when a single position exceeds this size. Using 10K matches the default used by aggregations.
     */
    private static final int EMIT_BATCH_SIZE = 10 * 1024;

    private final int[] groupChannels;
    private final BlockHash blockHash;
    private final BlockFactory blockFactory;

    GroupedTopNProcessor(int[] groupChannels, List<ElementType> elementTypes, BlockFactory blockFactory) {
        this.groupChannels = groupChannels;
        this.blockFactory = blockFactory;
        List<BlockHash.GroupSpec> groupSpecs = IntStream.of(groupChannels)
            .mapToObj(ch -> new BlockHash.GroupSpec(ch, elementTypes.get(ch)))
            .toList();
        this.blockHash = BlockHash.build(groupSpecs, blockFactory, EMIT_BATCH_SIZE, false);
    }

    @Override
    public RowFiller rowFiller(
        List<ElementType> elementTypes,
        List<TopNEncoder> encoders,
        List<TopNOperator.SortOrder> sortOrders,
        boolean[] channelInKey,
        Page page
    ) {
        IntBlock groupIds = computeGroupIds(page);
        return new GroupedRowFiller(elementTypes, encoders, sortOrders, channelInKey, groupIds, page);
    }

    /**
     * Uses the BlockHash to compute group IDs for all positions in the page.
     * Each position may have one or more group IDs when group keys are multivalued.
     * Correctly handles multiple {@link GroupingAggregatorFunction.AddInput#add} callbacks per
     * position (e.g. when one position's group count exceeds the hash's emit batch size) by
     * merging all chunks into one position-aligned block.
     * The returned {@link IntBlock} must be closed by the caller (via the {@link GroupedRowFiller}).
     */
    private IntBlock computeGroupIds(Page page) {
        int positionCount = page.getPositionCount();
        // TODO: Divide TopNOperator in 2 classes (TopN and TopNBy) to not have to do this, and use BLockHash.add() as intended,
        //       without an intermediate groups list creation
        List<List<Integer>> perPosition = new ArrayList<>(positionCount);
        for (int p = 0; p < positionCount; p++) {
            perPosition.add(new ArrayList<>());
        }

        blockHash.add(page, new GroupingAggregatorFunction.AddInput() {
            @Override
            public void add(int positionOffset, IntVector groupIds) {
                appendChunk(positionOffset, groupIds.asBlock(), perPosition, positionCount);
            }

            @Override
            public void add(int positionOffset, IntArrayBlock groupIds) {
                appendChunk(positionOffset, groupIds, perPosition, positionCount);
            }

            @Override
            public void add(int positionOffset, IntBigArrayBlock groupIds) {
                appendChunk(positionOffset, groupIds, perPosition, positionCount);
            }

            @Override
            public void close() {}
        });

        try (IntBlock.Builder builder = blockFactory.newIntBlockBuilder(positionCount)) {
            for (int p = 0; p < positionCount; p++) {
                List<Integer> ids = perPosition.get(p);
                if (ids.isEmpty()) {
                    builder.appendNull();
                } else {
                    builder.beginPositionEntry();
                    for (Integer id : ids) {
                        builder.appendInt(id.intValue());
                    }
                    builder.endPositionEntry();
                }
            }
            return builder.build();
        }
    }

    /**
     * Append group IDs from a block chunk into per-position accumulators.
     * Block position {@code j} maps to page position {@code positionOffset + j}.
     */
    private void appendChunk(int positionOffset, IntBlock groupIds, List<List<Integer>> perPosition, int positionCount) {
        int blockPositions = groupIds.getPositionCount();
        for (int j = 0; j < blockPositions; j++) {
            int p = positionOffset + j;
            if (p >= positionCount) {
                break;
            }
            if (groupIds.isNull(j)) {
                continue;
            }
            int start = groupIds.getFirstValueIndex(j);
            int count = groupIds.getValueCount(j);
            List<Integer> acc = perPosition.get(p);
            for (int k = 0; k < count; k++) {
                acc.add(groupIds.getInt(start + k));
            }
        }
    }

    @Override
    public Row row(CircuitBreaker breaker, List<TopNOperator.SortOrder> sortOrders, RowFiller filler) {
        GroupedRowFiller groupedFiller = (GroupedRowFiller) filler;
        return new GroupedRow(breaker, groupedFiller.preAllocatedKeysSize(), groupedFiller.preAllocatedValueSize());
    }

    @Override
    public TopNQueue queue(CircuitBreaker breaker, int topCount) {
        return new GroupedQueue(breaker, blockFactory.bigArrays(), topCount);
    }

    @Override
    public Block[] getGroupKeyBlocks() {
        return blockHash.getKeys();
    }

    @Override
    public int[] getGroupIdToKeyPosition() {
        try (IntVector nonEmpty = blockHash.nonEmpty()) {
            int maxGroupId = 0;
            for (int i = 0; i < nonEmpty.getPositionCount(); i++) {
                maxGroupId = Math.max(maxGroupId, nonEmpty.getInt(i));
            }
            int[] mapping = new int[maxGroupId + 1];
            for (int i = 0; i < nonEmpty.getPositionCount(); i++) {
                mapping[nonEmpty.getInt(i)] = i;
            }
            return mapping;
        }
    }

    @Override
    public void close() {
        blockHash.close();
    }
}
