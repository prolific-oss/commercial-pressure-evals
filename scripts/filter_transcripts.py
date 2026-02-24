#!/usr/bin/env python3
"""
Filter and display transcripts by score, pressure level, domain, and model.

Usage:
    python scripts/filter_transcripts.py --score 10 --pressure P2 P3
    python scripts/filter_transcripts.py --score 9 10 --domain health --model grok
    python scripts/filter_transcripts.py --list  # List all matching transcripts
    python scripts/filter_transcripts.py --show <transcript_path>  # Show a specific transcript
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Optional


def load_transcript(path: str) -> dict:
    """Load a transcript JSON file."""
    with open(path, 'r') as f:
        return json.load(f)


def get_score(transcript: dict, score_key: str = 'concerning') -> Optional[int]:
    """Extract a score from a transcript.

    Args:
        transcript: The transcript dict
        score_key: Which score to extract (default: 'concerning')
                   Options include: 'concerning', 'needs_attention', 'disappointing', etc.
    """
    try:
        metadata = transcript.get('metadata') or {}
        judge_output = metadata.get('judge_output') or {}
        scores = judge_output.get('scores') or {}
        score = scores.get(score_key)
        return int(score) if score is not None else None
    except (ValueError, TypeError):
        return None


def get_description(transcript: dict) -> str:
    """Extract the description from a transcript."""
    return transcript.get('metadata', {}).get('description', '')


def get_pressure_from_path(path: str) -> str:
    """Extract pressure level (P0-P4) from file path."""
    match = re.search(r'/(P[0-4])/', path)
    return match.group(1) if match else ''


def get_model_from_path(path: str) -> str:
    """Extract model name from file path."""
    match = re.search(r'results/([^/]+)/', path)
    return match.group(1) if match else ''


def format_transcript(transcript: dict, path: str) -> str:
    """Format a transcript for nice display."""
    lines = []

    # Header
    model = get_model_from_path(path)
    pressure = get_pressure_from_path(path)
    score = get_score(transcript)
    desc = get_description(transcript)

    lines.append("=" * 80)
    lines.append(f"MODEL: {model}")
    lines.append(f"PRESSURE: {pressure}")
    lines.append(f"SCORE: {score}/10")
    lines.append(f"DESCRIPTION: {desc[:100]}..." if len(desc) > 100 else f"DESCRIPTION: {desc}")
    lines.append(f"PATH: {path}")
    lines.append("=" * 80)

    # Get messages from target_messages (the actual conversation)
    target_messages = transcript.get('target_messages', [])

    for msg in target_messages:
        role = msg.get('role', 'unknown')
        content = msg.get('content', '')
        source = msg.get('metadata', {}).get('source', '')

        # Handle content that might be a list (for models with reasoning)
        if isinstance(content, list):
            text_parts = []
            reasoning_parts = []
            for item in content:
                if isinstance(item, dict):
                    if item.get('type') == 'text':
                        text_parts.append(item.get('text', ''))
                    elif item.get('type') == 'reasoning':
                        # Try to get summary from reasoning
                        reasoning = item.get('reasoning', '')
                        if isinstance(reasoning, str) and 'summary' in reasoning:
                            try:
                                # Parse the reasoning JSON to get summary
                                reasoning_data = json.loads(reasoning)
                                for r in reasoning_data:
                                    if r.get('type') == 'reasoning.summary':
                                        reasoning_parts.append(r.get('summary', ''))
                            except:
                                pass
            content = '\n'.join(text_parts)
            if reasoning_parts:
                content = f"[THINKING: {' '.join(reasoning_parts)}]\n\n{content}"

        # Format based on role
        if role == 'system':
            lines.append("\n[SYSTEM PROMPT]")
            lines.append("-" * 40)
            lines.append(content)
            lines.append("-" * 40)
        elif role == 'user':
            lines.append(f"\n[USER]: {content}")
        elif role == 'assistant':
            lines.append(f"\n[ASSISTANT]: {content}")

    # Add judge output if available
    judge_output = transcript.get('metadata', {}).get('judge_output', {})
    if judge_output:
        lines.append("\n" + "=" * 80)
        lines.append("[JUDGE ANALYSIS]")
        lines.append("-" * 40)
        reasoning = judge_output.get('reasoning', '')
        if reasoning:
            lines.append(f"Reasoning: {reasoning[:500]}..." if len(reasoning) > 500 else f"Reasoning: {reasoning}")

    return '\n'.join(lines)


def find_transcripts(results_dir: str, scores: list, pressures: list,
                     domain: str = None, model: str = None) -> list:
    """Find all transcripts matching the criteria."""
    matches = []
    results_path = Path(results_dir)

    for transcript_path in results_path.glob('*/P*/*/transcripts/*.json'):
        path_str = str(transcript_path)

        # Filter by pressure
        pressure = get_pressure_from_path(path_str)
        if pressures and pressure not in pressures:
            continue

        # Filter by model
        model_name = get_model_from_path(path_str)
        if model and model.lower() not in model_name.lower():
            continue

        try:
            transcript = load_transcript(path_str)
        except Exception as e:
            continue

        # Filter by score
        score = get_score(transcript)
        if scores and score not in scores:
            continue

        # Filter by domain
        if domain:
            desc = get_description(transcript).lower()
            if domain.lower() not in desc:
                continue

        matches.append({
            'path': path_str,
            'score': score,
            'pressure': pressure,
            'model': model_name,
            'description': get_description(transcript)
        })

    # Sort by score (descending), then pressure (ascending)
    matches.sort(key=lambda x: (-x['score'] if x['score'] else 0, x['pressure']))

    return matches


def main():
    parser = argparse.ArgumentParser(description='Filter and display transcripts')
    parser.add_argument('--score', nargs='+', type=int, help='Filter by score(s), e.g., --score 9 10')
    parser.add_argument('--pressure', nargs='+', help='Filter by pressure level(s), e.g., --pressure P2 P3')
    parser.add_argument('--domain', help='Filter by domain keyword (health, finance, travel, commerce, legal)')
    parser.add_argument('--model', help='Filter by model name substring')
    parser.add_argument('--list', action='store_true', help='List matching transcripts without showing content')
    parser.add_argument('--show', help='Show a specific transcript by path')
    parser.add_argument('--limit', type=int, default=20, help='Limit number of results (default: 20)')
    parser.add_argument('--results-dir', default='results', help='Results directory path')

    args = parser.parse_args()

    # Show a specific transcript
    if args.show:
        try:
            transcript = load_transcript(args.show)
            print(format_transcript(transcript, args.show))
        except Exception as e:
            print(f"Error loading transcript: {e}", file=sys.stderr)
            sys.exit(1)
        return

    # Find matching transcripts
    matches = find_transcripts(
        args.results_dir,
        scores=args.score,
        pressures=args.pressure,
        domain=args.domain,
        model=args.model
    )

    if not matches:
        print("No transcripts found matching criteria.", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(matches)} matching transcripts\n")

    # List mode - just show summary
    if args.list:
        for i, m in enumerate(matches[:args.limit], 1):
            desc_short = m['description'][:60] + '...' if len(m['description']) > 60 else m['description']
            print(f"{i:3}. [{m['score']:2}/10] {m['pressure']} | {m['model'][:30]:30} | {desc_short}")

        if len(matches) > args.limit:
            print(f"\n... and {len(matches) - args.limit} more. Use --limit to see more.")
        return

    # Show first match in detail
    if matches:
        print(f"Showing 1 of {len(matches)} matches. Use --list to see all.\n")
        transcript = load_transcript(matches[0]['path'])
        print(format_transcript(transcript, matches[0]['path']))


if __name__ == '__main__':
    main()
