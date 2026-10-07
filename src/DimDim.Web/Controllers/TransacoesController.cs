using DimDim.Web.Data;
using DimDim.Web.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;

namespace DimDim.Web.Controllers;

public class TransacoesController(DimDimContext context) : Controller
{
    public async Task<IActionResult> Index() =>
        View(await context.Transacoes.Include(t => t.Conta).OrderByDescending(t => t.Data).ThenByDescending(t => t.Id).ToListAsync());

    public async Task<IActionResult> Details(int? id)
    {
        if (id is null) return NotFound();
        var item = await context.Transacoes.Include(t => t.Conta).FirstOrDefaultAsync(t => t.Id == id);
        return item is null ? NotFound() : View(item);
    }

    public async Task<IActionResult> Create()
    {
        await LoadContas();
        return View(new Transacao());
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Create([Bind("Descricao,Valor,Data,Tipo,ContaId")] Transacao item)
    {
        if (!await context.Contas.AnyAsync(c => c.Id == item.ContaId))
            ModelState.AddModelError(nameof(item.ContaId), "Selecione uma conta válida.");
        if (!ModelState.IsValid) { await LoadContas(item.ContaId); return View(item); }
        context.Add(item);
        await context.SaveChangesAsync();
        TempData["Success"] = "Transação criada com sucesso.";
        return RedirectToAction(nameof(Index));
    }

    public async Task<IActionResult> Edit(int? id)
    {
        if (id is null) return NotFound();
        var item = await context.Transacoes.FindAsync(id);
        if (item is null) return NotFound();
        await LoadContas(item.ContaId);
        return View(item);
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Edit(int id, [Bind("Id,Descricao,Valor,Data,Tipo,ContaId")] Transacao item)
    {
        if (id != item.Id) return NotFound();
        if (!await context.Contas.AnyAsync(c => c.Id == item.ContaId))
            ModelState.AddModelError(nameof(item.ContaId), "Selecione uma conta válida.");
        if (!ModelState.IsValid) { await LoadContas(item.ContaId); return View(item); }
        try { context.Update(item); await context.SaveChangesAsync(); }
        catch (DbUpdateConcurrencyException)
        {
            if (!await context.Transacoes.AnyAsync(t => t.Id == id)) return NotFound();
            throw;
        }
        TempData["Success"] = "Transação atualizada com sucesso.";
        return RedirectToAction(nameof(Index));
    }

    [HttpPost, ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(int id)
    {
        var item = await context.Transacoes.FindAsync(id);
        if (item is null) return NotFound();
        context.Remove(item);
        await context.SaveChangesAsync();
        TempData["Success"] = "Transação excluída com sucesso.";
        return RedirectToAction(nameof(Index));
    }

    private async Task LoadContas(int? selected = null) =>
        ViewBag.ContaId = new SelectList(await context.Contas.OrderBy(c => c.Nome).ToListAsync(), "Id", "Nome", selected);
}
