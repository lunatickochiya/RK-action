'use strict';
'require view';
'require rpc';
'require poll';

var callStatus = rpc.declare({
	object: 'npu_status',
	method: 'status',
	expect: { }
});

var prevTasks = {};
var prevTime = null;

function fmtMHz(v) {
	v = +v || 0;
	return v ? (v / 1000000).toFixed(0) + ' MHz' : '—';
}

function fmtTemp(v) {
	v = +v || 0;
	return v ? (v / 1000).toFixed(1) + ' °C' : '—';
}

function barRow(id, label) {
	return E('div', { 'style': 'display:flex;align-items:center;margin:4px 0' }, [
		E('span', { 'style': 'width:80px;flex:none' }, [ label ]),
		E('div', { 'style': 'flex:1;height:16px;background:#eee;border-radius:4px;overflow:hidden;margin-right:8px' }, [
			E('div', { 'id': 'fill-' + id, 'style': 'height:100%;width:0%;background:#5cb85c;transition:width .3s' }, [])
		]),
		E('span', { 'id': 'val-' + id, 'style': 'width:56px;text-align:right' }, [ '—' ])
	]);
}

function coreRow(prefix, label) {
	return E('div', { 'style': 'display:flex;align-items:center;margin:3px 0;font-size:13px' }, [
		E('span', { 'style': 'width:110px;flex:none' }, [ label ]),
		E('span', { 'id': prefix + '-clk', 'style': 'width:90px' }, [ '—' ]),
		E('span', { 'id': prefix + '-tasks', 'style': 'width:120px' }, [ '—' ]),
		E('span', { 'id': prefix + '-rate', 'style': 'width:110px' }, [ '—' ])
	]);
}

return view.extend({
	load: function() {
		return callStatus();
	},

	render: function(data) {
		var viewEl = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [ 'NPU / VPU' ]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ 'RKNPU（AI 推理）' ]),
				E('div', { 'id': 'npu-ver', 'style': 'font-size:12px;opacity:.7;margin-bottom:6px' }, [ data.npu_ver || '' ]),
				barRow('core0', 'Core 0'),
				barRow('core1', 'Core 1'),
				barRow('core2', 'Core 2')
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ 'VPU（视频编解码 · rk_vcodec）' ]),
				E('div', { 'id': 'vpu-ver', 'style': 'font-size:12px;opacity:.7;margin-bottom:6px' }, [ data.vpu_ver || '' ]),
				E('div', { 'style': 'display:flex;font-size:12px;opacity:.7;margin:4px 0' }, [
					E('span', { 'style': 'width:110px' }, [ '核心' ]),
					E('span', { 'style': 'width:90px' }, [ '时钟' ]),
					E('span', { 'style': 'width:120px' }, [ '累计任务' ]),
					E('span', { 'style': 'width:110px' }, [ '速率' ])
				]),
				coreRow('dec0', '解码 Core0'),
				coreRow('dec1', '解码 Core1'),
				coreRow('enc0', '编码 Core0'),
				coreRow('enc1', '编码 Core1'),
				E('div', { 'style': 'margin-top:8px' }, [
					E('div', { 'style': 'font-size:12px;opacity:.7' }, [ '活动会话：' ]),
					E('pre', { 'id': 'vpu-sessions', 'style': 'white-space:pre-wrap;font-size:12px;margin:2px 0;max-height:140px;overflow:auto' }, [ data.vpu_sessions || '（无）' ])
				])
			]),

			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, [ '温度 / 负载' ]),
				E('div', { 'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:6px;font-size:13px' }, [
					E('div', {}, [ 'SoC 封装：', E('b', { 'id': 't-package' }, [ '—' ]) ]),
					E('div', {}, [ 'NPU：', E('b', { 'id': 't-npu' }, [ '—' ]) ]),
					E('div', {}, [ 'GPU：', E('b', { 'id': 't-gpu' }, [ '—' ]) ]),
					E('div', {}, [ '大核0：', E('b', { 'id': 't-big0' }, [ '—' ]) ]),
					E('div', {}, [ '大核2：', E('b', { 'id': 't-big2' }, [ '—' ]) ]),
					E('div', {}, [ '小核：', E('b', { 'id': 't-little' }, [ '—' ]) ]),
					E('div', {}, [ 'Center：', E('b', { 'id': 't-center' }, [ '—' ]) ]),
					E('div', {}, [ 'Load：', E('b', { 'id': 'loadavg' }, [ '—' ]) ])
				])
			])
		]);

		function setBar(id, pct) {
			var fill = document.getElementById('fill-' + id);
			var val = document.getElementById('val-' + id);
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

		function setCore(prefix, clk, tasks) {
			setText(prefix + '-clk', fmtMHz(clk));
			setText(prefix + '-tasks', String(tasks || 0));
			var prev = prevTasks[prefix];
			prevTasks[prefix] = tasks || 0;
			if (prev === undefined || prevTime === null) {
				setText(prefix + '-rate', '—');
				return;
			}
			var dt = (Date.now() / 1000) - prevTime;
			var rate = dt > 0 ? Math.max(0, ((tasks || 0) - prev) / dt) : 0;
			setText(prefix + '-rate', rate.toFixed(1) + ' 任务/s');
		}

		function update(d) {
			setBar('core0', d.core0);
			setBar('core1', d.core1);
			setBar('core2', d.core2);
			setText('npu-ver', d.npu_ver);
			setText('vpu-ver', d.vpu_ver);

			setCore('dec0', d.dec0_clk, d.dec0_tasks);
			setCore('dec1', d.dec1_clk, d.dec1_tasks);
			setCore('enc0', d.enc0_clk, d.enc0_tasks);
			setCore('enc1', d.enc1_clk, d.enc1_tasks);
			prevTime = Date.now() / 1000;

			setText('vpu-sessions', d.vpu_sessions || '（无）');
			setText('t-package', fmtTemp(d.temp_package));
			setText('t-npu', fmtTemp(d.temp_npu));
			setText('t-gpu', fmtTemp(d.temp_gpu));
			setText('t-big0', fmtTemp(d.temp_big0));
			setText('t-big2', fmtTemp(d.temp_big2));
			setText('t-little', fmtTemp(d.temp_little));
			setText('t-center', fmtTemp(d.temp_center));
			setText('loadavg', d.loadavg);
		}

		update(data);

		poll.add(function() {
			return callStatus().then(function(d) {
				update(d);
				return d;
			});
		}, 3);

		return viewEl;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
