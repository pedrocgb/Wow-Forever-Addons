// Harvest hunter pet data from Wowhead Forever. Run in the browser console (or via Claude in Chrome)
// on https://www.wowhead.com/forever/spells/pet-abilities/hunter, then feed the JSON to build_petdata.py:
//   python3 tools/build_petdata.py harvest.json > PetData.lua
// Wowhead rate-limits: keep the delay at >= 3 s. If a "Human Verification" page shows up the loop stops;
// solve it in the browser yourself and rerun with the remaining ids (HARVEST.todo).
(async () => {
	// Pull one `new Listview({ id: '<id>', ... data: [...] })` block out of a page's HTML.
	const listview = (html, id) => {
		const i = html.indexOf("id: '" + id + "'");
		if (i < 0) return null;
		const j = html.indexOf('[', html.indexOf('data:', i));
		let depth = 0, k = j, quote = null;
		for (; k < html.length; k++) {
			const c = html[k];
			if (quote) { if (c === '\\') k++; else if (c === quote) quote = null; continue; }
			if (c === '"' || c === "'") quote = c;
			else if (c === '[') depth++;
			else if (c === ']' && --depth === 0) break;
		}
		return new Function('return ' + html.slice(j, k + 1))();
	};

	const list = window.listviewspells.map(s =>
		[s.id, s.name, s.rank, s.level, s.skill, s.envChange && s.envChange.status]);
	const H = window.HARVEST = { list, spells: {}, fams: {}, npcs: {}, todo: list.map(s => s[0]) };

	while (H.todo.length) {
		const id = H.todo[0];
		const r = await fetch('/forever/spell=' + id);
		const html = await r.text();
		if (r.status !== 200 || /<title>Human Verification/.test(html)) {
			console.warn('stopped at', id, r.status); return;
		}
		const pet = listview(html, 'used-by-pet') || [];   // families that can learn it
		const npc = listview(html, 'used-by-npc') || [];   // creatures that know it (tame these)
		const tb = listview(html, 'taught-by-npc') || [];  // pet trainers
		H.spells[id] = { fams: pet.map(p => p.id), npcs: npc.map(n => n.id), trainers: tb.length };
		for (const p of pet) H.fams[p.id] = { name: p.name, diet: p.diet, armor: p.armor, damage: p.damage, health: p.health, type: p.type };
		for (const n of npc) H.npcs[n.id] = { name: n.name, family: n.family, min: n.minlevel, max: n.maxlevel,
			loc: n.location, cls: n.classification, react: n.react, type: n.type };
		H.todo.shift();
		await new Promise(res => setTimeout(res, 3000));
	}
	console.log('done: copy(JSON.stringify(HARVEST)) and save it as harvest.json');
})();
