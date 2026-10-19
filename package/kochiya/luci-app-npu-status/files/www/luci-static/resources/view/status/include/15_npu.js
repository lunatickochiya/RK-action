'use strict';
'require baseclass';
'require rpc';

var callStatus = rpc.declare({
	object: 'npu_status',
	method: 'status',
	expect: {}
});

var fastTimer = null;

function fmtMHz(v) {
	v = +v || 0;
	return v ? (v / 1000000).toFixed(0) + ' MHz' : '—';
}

function fmtTemp(v) {
	v = +v || 0;
	return v ? (v / 1000).toFixed(1) + ' °C' : '—';
}

function setBar(id, pct) {
	var fill = document.getElementById('npu-fill-' + id);
	var val = document.getElementById('npu-val-' + id);
	pct = Math.max(0, Math.min(100, +pct || 0));
	if (fill) {
		fill.style.width = pct + '%';
		fill.style.background = pct >= 80 ? '#d9534f' : (pct >= 50 ? '#f0ad4e' : '#5cb85c');
	}
	if (val)
		val.textContent = pct + '%';
}

function setText(id, txt) {
	var el = document.getElementById(id);
	if (el)
		el.textContent = (txt == null || txt === '') ? '—' : txt;
}

function applyData(d) {
	setBar('c0', d.core0);
	setBar('c1', d.core1);
	setBar('c2', d.core2);
	setText('npu-drv', (d.npu_ver || '—') + ' · ' + fmtMHz(d.npu_freq));
	setText('vpu-dec', 'Core0 ' + fmtMHz(d.dec0_clk) + ' · ' + (d.dec0_tasks || 0) + ' 任务　Core1 ' + fmtMHz(d.dec1_clk) + ' · ' + (d.dec1_tasks || 0) + ' 任务');
	setText('vpu-enc', 'Core0 ' + fmtMHz(d.enc0_clk) + ' · ' + (d.enc0_tasks || 0) + ' 会话　Core1 ' + fmtMHz(d.enc1_clk) + ' · ' + (d.enc1_tasks || 0) + ' 会话');
	setText('vpu-sess', String(((d.vpu_sessions || '').match(/session:/g) || []).length));
	setText('temps', 'SoC ' + fmtTemp(d.temp_package) + ' · NPU ' + fmtTemp(d.temp_npu) + ' · GPU ' + fmtTemp(d.temp_gpu));
	setText('loadavg', d.loadavg || '—');
}

function startFastPoll() {
	if (fastTimer)
		return;
	fastTimer = setInterval(function() {
		if (document.hidden || !document.getElementById('npu-fast-root'))
			return;
		callStatus().then(applyData).catch(function() {});
	}, 1000);
}

function barRow(id, label) {
	return E('div', { 'style': 'display:flex;align-items:center;margin:2px 0' }, [
		E('span', { 'style': 'width:64px;flex:none' }, [ label ]),
		E('div', { 'class': 'cbi-progressbar', 'style': 'flex:1' }, [
			E('div', { 'id': 'npu-fill-' + id, 'style': 'width:0%' }, [])
		]),
		E('span', { 'id': 'npu-val-' + id, 'style': 'width:44px;text-align:right' }, [ '0%' ])
	]);
}

function row(label, valueEl) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'width': '33%' }, [ label ]),
		E('td', { 'class': 'td left' }, [ valueEl ])
	]);
}

return baseclass.extend({
	title: 'NPU / VPU',

	load: function() {
		return L.resolveDefault(callStatus(), {});
	},

	render: function(d) {
		var table = E('div', { 'id': 'npu-fast-root' }, [
			barRow('c0', 'Core 0'),
			barRow('c1', 'Core 1'),
			barRow('c2', 'Core 2'),
			E('table', { 'class': 'table' }, [
				row('NPU 驱动', E('span', { 'id': 'npu-drv' })),
				row('VPU 解码', E('span', { 'id': 'vpu-dec' })),
				row('VPU 编码', E('span', { 'id': 'vpu-enc' })),
				row('VPU 活动会话', E('span', { 'id': 'vpu-sess' })),
				row('温度', E('span', { 'id': 'temps' })),
				row('Load', E('span', { 'id': 'loadavg' }))
			])
		]);

		applyData(d || {});
		startFastPoll();
		return table;
	}
});
